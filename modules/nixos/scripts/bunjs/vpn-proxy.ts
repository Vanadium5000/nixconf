#!/usr/bin/env bun
/**
 * VPN SOCKS5 Proxy Server
 *
 * Architecture:
 * ┌─────────────┐     ┌──────────────┐     ┌─────────────────┐
 * │ Client App  │────▶│ SOCKS5 Proxy │────▶│ Network Namespace│
 * │ (curl, etc) │     │ (this file)  │     │ (vpn-proxy-N)   │
 * └─────────────┘     └──────────────┘     └────────┬────────┘
 *                                                   │
 *                     Username = VPN slug           ▼
 *                     "random" = rotating      ┌─────────┐
 *                                              │ OpenVPN │
 *                                              │ Tunnel  │
 *                                              └────┬────┘
 *                                                   ▼
 *                                              Internet
 *
 * Security Model:
 * - Each VPN runs in isolated network namespace
 * - nftables kill-switch blocks all non-VPN traffic
 * - DNS configured per-namespace to prevent leaks
 * - Namespace destroyed on idle timeout
 *
 * SOCKS5 Protocol (RFC 1928):
 * - Version: 0x05
 * - Auth method 0x02: Username/Password (RFC 1929)
 * - Command 0x01: CONNECT (only supported command)
 * - Address types: 0x01 (IPv4), 0x03 (domain), 0x04 (IPv6 - unsupported)
 *
 * Known Limitations:
 * - IPv6 destinations not supported (would need IPv6 in namespace)
 * - UDP ASSOCIATE (0x03) not implemented
 * - BIND (0x02) not implemented
 * - State file has no locking (race condition on concurrent first-requests)
 */

import { spawn, spawnSync } from "bun";
import { readFile, writeFile, mkdir, unlink } from "fs/promises";
import { join } from "path";
import { createServer, type Socket } from "net";
import {
  listVpns,
  resolveVpn,
  getRandomVpn,
  isValidSlug,
  type VpnConfig,
} from "./vpn-resolver";

// State stored in tmpfs for speed and automatic cleanup on reboot
const STATE_DIR = `/dev/shm/vpn-proxy-${process.getuid!()}`;
const STATE_FILE = join(STATE_DIR, "state.json");
const NETNS_SCRIPT =
  process.env.VPN_PROXY_NETNS_SCRIPT ||
  join(import.meta.dir, "vpn-proxy-netns.sh");

const PROXY_PORT = parseInt(process.env.VPN_PROXY_PORT || "10800", 10);
const IDLE_TIMEOUT = parseInt(process.env.VPN_PROXY_IDLE_TIMEOUT || "300", 10);
const RANDOM_ROTATION = parseInt(
  process.env.VPN_PROXY_RANDOM_ROTATION || "300",
  10
);

interface NamespaceInfo {
  nsName: string;
  nsIndex: number;
  nsIp: string;
  slug: string;
  vpnDisplayName: string;
  lastUsed: number;
  openvpnPid: number;
  status: "starting" | "connected" | "failed";
}

interface ProxyState {
  namespaces: Record<string, NamespaceInfo>;
  random: { currentSlug: string; expiresAt: number } | null;
  nextIndex: number;
}

function log(
  level: "DEBUG" | "INFO" | "WARN" | "ERROR",
  message: string
): void {
  const timestamp = new Date().toISOString();
  console.error(`[${timestamp}] [${level}] [vpn-proxy] ${message}`);
}

async function ensureStateDir(): Promise<void> {
  await mkdir(STATE_DIR, { recursive: true }).catch(() => {});
}

async function loadState(): Promise<ProxyState> {
  try {
    const content = await readFile(STATE_FILE, "utf-8");
    return JSON.parse(content);
  } catch {
    return { namespaces: {}, random: null, nextIndex: 0 };
  }
}

async function saveState(state: ProxyState): Promise<void> {
  await ensureStateDir();
  await writeFile(STATE_FILE, JSON.stringify(state, null, 2));
}

function runNetnsScript(args: string[]): { success: boolean; output: string } {
  const sudoPrefix = process.getuid!() === 0 ? [] : ["sudo"];
  const result = spawnSync([...sudoPrefix, "bash", NETNS_SCRIPT, ...args]);
  const output = result.stdout.toString() + result.stderr.toString();
  return { success: result.exitCode === 0, output };
}

async function createNamespace(
  state: ProxyState,
  vpn: VpnConfig
): Promise<NamespaceInfo> {
  const nsIndex = state.nextIndex;
  const nsName = `vpn-proxy-${nsIndex}`;
  const nsIp = `10.200.${nsIndex}.2`;

  log("INFO", `Creating namespace ${nsName} for ${vpn.displayName}`);

  const result = runNetnsScript([
    "create",
    nsName,
    nsIndex.toString(),
    vpn.serverIp,
    vpn.serverPort.toString(),
  ]);

  if (!result.success) {
    log("ERROR", `Failed to create namespace: ${result.output}`);
    throw new Error(`Namespace creation failed`);
  }

  const openvpnPid = await startOpenVPN(nsName, vpn);
  const tunnelUp = await waitForTunnel(nsName);

  if (!tunnelUp) {
    runNetnsScript(["destroy", nsName]);
    throw new Error("VPN tunnel failed to establish");
  }

  const info: NamespaceInfo = {
    nsName,
    nsIndex,
    nsIp,
    slug: vpn.slug,
    vpnDisplayName: vpn.displayName,
    lastUsed: Date.now(),
    openvpnPid,
    status: "connected",
  };

  state.namespaces[vpn.slug] = info;
  state.nextIndex++;
  await saveState(state);

  log("INFO", `Namespace ${nsName} ready for ${vpn.displayName}`);
  return info;
}

async function startOpenVPN(nsName: string, vpn: VpnConfig): Promise<number> {
  log("INFO", `Starting OpenVPN in ${nsName}`);

  const pidFile = join(STATE_DIR, `openvpn-${nsName}.pid`);
  const logFile = join(STATE_DIR, `openvpn-${nsName}.log`);

  const sudoPrefix = process.getuid!() === 0 ? [] : ["sudo"];
  const proc = spawn({
    cmd: [
      ...sudoPrefix,
      "ip",
      "netns",
      "exec",
      nsName,
      "openvpn",
      "--config",
      vpn.ovpnPath,
      "--dev",
      "tun0",
      "--daemon",
      "--writepid",
      pidFile,
      "--log",
      logFile,
    ],
    stdout: "ignore",
    stderr: "pipe",
  });

  await proc.exited;

  if (proc.exitCode !== 0) {
    const stderr = await new Response(proc.stderr).text();
    throw new Error(`OpenVPN failed: ${stderr}`);
  }

  await Bun.sleep(2000);

  try {
    const pid = parseInt(await readFile(pidFile, "utf-8"), 10);
    log("INFO", `OpenVPN started with PID ${pid}`);
    return pid;
  } catch {
    throw new Error("OpenVPN PID file not found");
  }
}

async function waitForTunnel(
  nsName: string,
  timeout = 30000
): Promise<boolean> {
  const start = Date.now();
  const sudoPrefix = process.getuid!() === 0 ? [] : ["sudo"];
  while (Date.now() - start < timeout) {
    const result = spawnSync([
      ...sudoPrefix,
      "ip",
      "netns",
      "exec",
      nsName,
      "ip",
      "addr",
      "show",
      "tun0",
    ]);
    if (result.exitCode === 0) {
      log("INFO", `Tunnel tun0 up in ${nsName}`);
      return true;
    }
    await Bun.sleep(500);
  }
  log("ERROR", `Timeout waiting for tunnel in ${nsName}`);
  return false;
}

async function destroyNamespace(
  slug: string,
  state: ProxyState
): Promise<void> {
  const info = state.namespaces[slug];
  if (!info) return;

  log("INFO", `Destroying namespace for ${slug}`);
  runNetnsScript(["destroy", info.nsName]);

  delete state.namespaces[slug];
  await saveState(state);
}

async function getOrCreateNamespace(
  slug: string,
  state: ProxyState
): Promise<NamespaceInfo> {
  const existing = state.namespaces[slug];
  if (existing && existing.status === "connected") {
    existing.lastUsed = Date.now();
    await saveState(state);
    return existing;
  }

  const vpn = await resolveVpn(slug);
  if (!vpn) throw new Error(`VPN not found: ${slug}`);

  return createNamespace(state, vpn);
}

async function resolveSlugFromUsername(
  username: string,
  state: ProxyState
): Promise<string> {
  if (!username || username === "random") {
    const now = Date.now();
    if (state.random && state.random.expiresAt > now) {
      return state.random.currentSlug;
    }

    const vpn = await getRandomVpn();
    if (!vpn) throw new Error("No VPNs available");

    state.random = {
      currentSlug: vpn.slug,
      expiresAt: now + RANDOM_ROTATION * 1000,
    };
    await saveState(state);
    log("INFO", `Random VPN selected: ${vpn.displayName}`);
    return vpn.slug;
  }

  const isValid = await isValidSlug(username);
  if (!isValid) {
    // TODO: notify-send not in systemd PATH - log only for now
    log("WARN", `Invalid slug "${username}", falling back to random`);
    return resolveSlugFromUsername("random", state);
  }

  return username;
}

function parseSocks5Auth(
  data: Buffer
): { username: string; password: string } | null {
  if (data.length < 5) return null;
  const version = data[0];
  if (version !== 0x01) return null;

  const ulen = data[1]!;
  if (data.length < 2 + ulen + 1) return null;

  const username = data.subarray(2, 2 + ulen).toString("utf-8");
  const plen = data[2 + ulen]!;
  if (data.length < 3 + ulen + plen) return null;

  const password = data.subarray(3 + ulen, 3 + ulen + plen).toString("utf-8");
  return { username, password };
}

import type { FileSink } from "bun";

interface NamespaceConnection {
  stdin: FileSink;
  stdout: ReadableStream<Uint8Array>;
  proc: ReturnType<typeof spawn>;
}

async function connectThroughNamespace(
  nsInfo: NamespaceInfo,
  targetHost: string,
  targetPort: number
): Promise<NamespaceConnection> {
  const sudoPrefix = process.getuid!() === 0 ? [] : ["sudo"];
  const args = [
    ...sudoPrefix,
    "ip",
    "netns",
    "exec",
    nsInfo.nsName,
    "socat",
    "-",
    `TCP:${targetHost}:${targetPort}`,
  ];

  const proc = spawn({
    cmd: args,
    stdin: "pipe",
    stdout: "pipe",
    stderr: "pipe",
  });

  return {
    stdin: proc.stdin as FileSink,
    stdout: proc.stdout as ReadableStream<Uint8Array>,
    proc,
  };
}

async function handleConnection(
  clientSocket: Socket,
  state: ProxyState
): Promise<void> {
  let username = "";

  clientSocket.once("data", async (data: Buffer) => {
    try {
      if (data[0] !== 0x05) {
        clientSocket.end();
        return;
      }

      const nmethods = data[1]!;
      const methods = data.subarray(2, 2 + nmethods);
      const supportsAuth = methods.includes(0x02);

      if (supportsAuth) {
        clientSocket.write(Buffer.from([0x05, 0x02]));

        clientSocket.once("data", async (authData: Buffer) => {
          const auth = parseSocks5Auth(authData);
          if (auth) {
            username = auth.username;
          }
          clientSocket.write(Buffer.from([0x01, 0x00]));
          await handleSocks5Request(clientSocket, username, state);
        });
      } else {
        clientSocket.write(Buffer.from([0x05, 0x00]));
        await handleSocks5Request(clientSocket, "", state);
      }
    } catch (error) {
      log("ERROR", `Connection error: ${error}`);
      clientSocket.end();
    }
  });
}

async function handleSocks5Request(
  clientSocket: Socket,
  username: string,
  state: ProxyState
): Promise<void> {
  clientSocket.once("data", async (data: Buffer) => {
    try {
      if (data[0] !== 0x05 || data[1] !== 0x01) {
        clientSocket.write(
          Buffer.from([0x05, 0x07, 0x00, 0x01, 0, 0, 0, 0, 0, 0])
        );
        clientSocket.end();
        return;
      }

      const atyp = data[3];
      let targetHost: string;
      let targetPort: number;
      let addrEnd: number;

      if (atyp === 0x01) {
        targetHost = `${data[4]}.${data[5]}.${data[6]}.${data[7]}`;
        addrEnd = 8;
      } else if (atyp === 0x03) {
        const domainLen = data[4]!;
        targetHost = data.subarray(5, 5 + domainLen).toString("utf-8");
        addrEnd = 5 + domainLen;
      } else if (atyp === 0x04) {
        clientSocket.write(
          Buffer.from([0x05, 0x08, 0x00, 0x01, 0, 0, 0, 0, 0, 0])
        );
        clientSocket.end();
        return;
      } else {
        clientSocket.end();
        return;
      }

      targetPort = (data[addrEnd]! << 8) | data[addrEnd + 1]!;

      log(
        "DEBUG",
        `SOCKS5 request: ${username || "random"}@${targetHost}:${targetPort}`
      );

      const slug = await resolveSlugFromUsername(username, state);
      const nsInfo = await getOrCreateNamespace(slug, state);

      const reply = Buffer.from([0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
      clientSocket.write(reply);

      const { stdin, stdout, proc } = await connectThroughNamespace(
        nsInfo,
        targetHost,
        targetPort
      );

      clientSocket.on("data", (chunk: Buffer) => {
        stdin!.write(chunk);
      });

      const reader = stdout.getReader();
      (async () => {
        try {
          while (true) {
            const { done, value } = await reader.read();
            if (done) break;
            if (!clientSocket.destroyed) {
              clientSocket.write(Buffer.from(value));
            }
          }
        } catch {}
        clientSocket.end();
      })();

      clientSocket.on("close", () => {
        stdin!.end();
        proc.kill();
      });
      clientSocket.on("error", () => {
        stdin!.end();
        proc.kill();
      });

      proc.exited.then(() => {
        if (!clientSocket.destroyed) clientSocket.end();
      });
    } catch (error) {
      log("ERROR", `Request error: ${error}`);
      clientSocket.write(
        Buffer.from([0x05, 0x01, 0x00, 0x01, 0, 0, 0, 0, 0, 0])
      );
      clientSocket.end();
    }
  });
}

export async function cleanupIdleProxies(): Promise<number> {
  const state = await loadState();
  const now = Date.now();
  const threshold = now - IDLE_TIMEOUT * 1000;
  let cleaned = 0;

  for (const [slug, info] of Object.entries(state.namespaces)) {
    if (info.lastUsed < threshold) {
      log("INFO", `Cleaning idle: ${slug}`);
      await destroyNamespace(slug, state);
      cleaned++;
    }
  }

  return cleaned;
}

export async function rotateRandom(): Promise<void> {
  const state = await loadState();
  if (!state.random) return;

  const now = Date.now();
  if (state.random.expiresAt <= now) {
    const oldSlug = state.random.currentSlug;
    const vpn = await getRandomVpn();
    if (vpn && vpn.slug !== oldSlug) {
      state.random = {
        currentSlug: vpn.slug,
        expiresAt: now + RANDOM_ROTATION * 1000,
      };
      await saveState(state);
      log("INFO", `Random rotated: ${oldSlug} -> ${vpn.displayName}`);
    }
  }
}

export async function getStatus(): Promise<string> {
  const state = await loadState();
  const now = Date.now();

  let output = `VPN SOCKS5 Proxy Status\n${"=".repeat(50)}\n`;
  output += `Listening: localhost:${PROXY_PORT}\n\n`;

  const namespaces = Object.values(state.namespaces);
  if (namespaces.length === 0) {
    output += "Active VPNs: (none)\n";
  } else {
    output += "Active VPNs:\n";
    for (const ns of namespaces) {
      const idleSecs = Math.floor((now - ns.lastUsed) / 1000);
      const idleMin = Math.floor(idleSecs / 60);
      const idleSec = idleSecs % 60;
      const isRandom = state.random?.currentSlug === ns.slug ? " (random)" : "";
      output += `  ${ns.vpnDisplayName}  idle: ${idleMin}m ${idleSec}s  status: ${ns.status}${isRandom}\n`;
    }
  }

  if (state.random) {
    const expiresIn = Math.max(
      0,
      Math.floor((state.random.expiresAt - now) / 1000)
    );
    const expMin = Math.floor(expiresIn / 60);
    const expSec = expiresIn % 60;
    output += `\nRandom VPN: ${state.random.currentSlug} (expires in ${expMin}m ${expSec}s)\n`;
  }

  output += `\nState: ${STATE_DIR}/\n`;
  output += `Idle timeout: ${IDLE_TIMEOUT}s\n`;

  return output;
}

export async function stopAllProxies(): Promise<void> {
  log("INFO", "Stopping all proxies");
  runNetnsScript(["cleanup-all"]);
  await unlink(STATE_FILE).catch(() => {});
}

async function startServer(): Promise<void> {
  await ensureStateDir();
  const state = await loadState();

  const server = createServer((socket) => {
    handleConnection(socket, state);
  });

  server.listen(PROXY_PORT, "127.0.0.1", () => {
    log("INFO", `SOCKS5 proxy listening on 127.0.0.1:${PROXY_PORT}`);
  });

  server.on("error", (err) => {
    log("ERROR", `Server error: ${err}`);
    process.exit(1);
  });

  process.on("SIGTERM", async () => {
    log("INFO", "Shutting down...");
    server.close();
    process.exit(0);
  });

  process.on("SIGINT", async () => {
    log("INFO", "Shutting down...");
    server.close();
    process.exit(0);
  });
}

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  const command = args[0];

  if (args.includes("--help") || args.includes("-h")) {
    console.log(`VPN SOCKS5 Proxy - Routes traffic through VPNs via username authentication

Usage:
  vpn-proxy [command]

Commands:
  serve       Start the SOCKS5 proxy server (default if no command)
  status      Show active VPN proxies and their idle times
  stop-all    Stop all VPN proxies and clean up namespaces

Options:
  -h, --help  Show this help message

Environment:
  VPN_DIR                    VPN configs directory (default: ~/Shared/VPNs)
  VPN_PROXY_PORT             Listening port (default: 10800)
  VPN_PROXY_IDLE_TIMEOUT     Idle cleanup timeout in seconds (default: 300)
  VPN_PROXY_RANDOM_ROTATION  Random VPN rotation interval (default: 300)

Examples:
  vpn-proxy serve                    # Start the proxy server
  vpn-proxy status                   # Check active VPNs
  
  # Use with curl (VPN name as username)
  curl --proxy "socks5://AirVPN%20AT%20Vienna@127.0.0.1:10800" https://api.ipify.org
  
  # Random VPN
  curl --proxy "socks5://random@127.0.0.1:10800" https://api.ipify.org
`);
    return;
  }

  switch (command) {
    case "status":
      console.log(await getStatus());
      break;
    case "stop-all":
      await stopAllProxies();
      console.log("All proxies stopped");
      break;
    case "serve":
      await startServer();
      break;
    default:
      if (command && command !== "serve") {
        console.error(
          `Unknown command: ${command}\nRun 'vpn-proxy --help' for usage.`
        );
        process.exit(1);
      }
      await startServer();
      break;
  }
}

if (import.meta.main) {
  main().catch((error) => {
    log("ERROR", `Fatal: ${error}`);
    process.exit(1);
  });
}
