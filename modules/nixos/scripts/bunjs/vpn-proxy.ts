#!/usr/bin/env bun
/**
 * VPN Proxy Manager - Core lifecycle management for SOCKS5 proxies
 * Handles port allocation, namespace orchestration, and state management
 */

import { spawn, spawnSync } from "bun";
import { readFile, writeFile, mkdir, unlink, readdir } from "fs/promises";
import { join } from "path";
import { listVpns, resolveVpn, getRandomVpn, type VpnConfig } from "./vpn-resolver";

const STATE_DIR = `/dev/shm/vpn-proxy-${process.getuid()}`;
const STATE_FILE = join(STATE_DIR, "state.json");
const RANDOM_FILE = join(STATE_DIR, "random.json");
const NETNS_SCRIPT = process.env.VPN_PROXY_NETNS_SCRIPT || join(import.meta.dir, "vpn-proxy-netns.sh");

const PORT_START = parseInt(process.env.VPN_PROXY_PORT_START || "10800", 10);
const PORT_END = parseInt(process.env.VPN_PROXY_PORT_END || "10899", 10);
const IDLE_TIMEOUT = parseInt(process.env.VPN_PROXY_IDLE_TIMEOUT || "300", 10);
const RANDOM_ROTATION = parseInt(process.env.VPN_PROXY_RANDOM_ROTATION || "300", 10);

interface ProxyState {
  slugToPort: Record<string, number>;
  portToSlug: Record<number, string>;
  portToNs: Record<number, string>;
  lastUsed: Record<number, number>;
  pids: Record<number, { openvpn: number; microsocks: number }>;
}

interface RandomState {
  slug: string;
  expiresAt: number;
}

function log(level: "DEBUG" | "INFO" | "WARN" | "ERROR", message: string): void {
  const timestamp = new Date().toISOString();
  console.error(`[${timestamp}] [${level}] [proxy-manager] ${message}`);
}

async function ensureStateDir(): Promise<void> {
  await mkdir(STATE_DIR, { recursive: true });
}

async function loadState(): Promise<ProxyState> {
  try {
    const content = await readFile(STATE_FILE, "utf-8");
    return JSON.parse(content);
  } catch {
    return { slugToPort: {}, portToSlug: {}, portToNs: {}, lastUsed: {}, pids: {} };
  }
}

async function saveState(state: ProxyState): Promise<void> {
  await ensureStateDir();
  await writeFile(STATE_FILE, JSON.stringify(state, null, 2));
}

async function loadRandomState(): Promise<RandomState | null> {
  try {
    const content = await readFile(RANDOM_FILE, "utf-8");
    return JSON.parse(content);
  } catch {
    return null;
  }
}

async function saveRandomState(state: RandomState): Promise<void> {
  await ensureStateDir();
  await writeFile(RANDOM_FILE, JSON.stringify(state, null, 2));
}

function findAvailablePort(state: ProxyState): number | null {
  for (let port = PORT_START; port <= PORT_END; port++) {
    if (!state.portToSlug[port]) {
      return port;
    }
  }
  return null;
}

function runNetnsScript(args: string[]): { success: boolean; output: string } {
  const result = spawnSync(["bash", NETNS_SCRIPT, ...args]);
  const output = result.stdout.toString() + result.stderr.toString();
  return { success: result.exitCode === 0, output };
}

async function createNamespace(port: number, vpn: VpnConfig): Promise<string> {
  const nsName = `vpn-proxy-${port - PORT_START}`;
  const nsIndex = port - PORT_START;
  
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
    throw new Error(`Namespace creation failed: ${result.output}`);
  }
  
  return nsName;
}

async function destroyNamespace(nsName: string): Promise<void> {
  log("INFO", `Destroying namespace ${nsName}`);
  runNetnsScript(["destroy", nsName]);
}

async function startOpenVPN(nsName: string, vpn: VpnConfig): Promise<number> {
  log("INFO", `Starting OpenVPN in ${nsName} for ${vpn.displayName}`);
  
  const proc = spawn({
    cmd: [
      "sudo", "ip", "netns", "exec", nsName,
      "openvpn",
      "--config", vpn.ovpnPath,
      "--dev", "tun0",
      "--daemon",
      "--writepid", join(STATE_DIR, `openvpn-${nsName}.pid`),
      "--log", join(STATE_DIR, `openvpn-${nsName}.log`),
    ],
    stdout: "ignore",
    stderr: "pipe",
  });
  
  await proc.exited;
  
  if (proc.exitCode !== 0) {
    const stderr = await new Response(proc.stderr).text();
    throw new Error(`OpenVPN failed to start: ${stderr}`);
  }
  
  await Bun.sleep(2000);
  
  try {
    const pidFile = join(STATE_DIR, `openvpn-${nsName}.pid`);
    const pid = parseInt(await readFile(pidFile, "utf-8"), 10);
    log("INFO", `OpenVPN started with PID ${pid}`);
    return pid;
  } catch {
    throw new Error("OpenVPN started but PID file not found");
  }
}

async function waitForTunnel(nsName: string, timeout = 30000): Promise<boolean> {
  const start = Date.now();
  
  while (Date.now() - start < timeout) {
    const result = spawnSync([
      "sudo", "ip", "netns", "exec", nsName,
      "ip", "addr", "show", "tun0",
    ]);
    
    if (result.exitCode === 0) {
      log("INFO", `Tunnel tun0 is up in ${nsName}`);
      return true;
    }
    
    await Bun.sleep(500);
  }
  
  log("ERROR", `Timeout waiting for tunnel in ${nsName}`);
  return false;
}

async function startMicrosocks(nsName: string, port: number, nsIndex: number): Promise<number> {
  const bindIp = `10.200.${nsIndex}.2`;
  
  log("INFO", `Starting microsocks on ${bindIp}:${port} in ${nsName}`);
  
  const proc = spawn({
    cmd: [
      "sudo", "ip", "netns", "exec", nsName,
      "microsocks",
      "-i", bindIp,
      "-p", port.toString(),
    ],
    stdout: "ignore",
    stderr: "pipe",
  });
  
  await Bun.sleep(500);
  
  if (proc.exitCode !== null && proc.exitCode !== 0) {
    const stderr = await new Response(proc.stderr).text();
    throw new Error(`microsocks failed to start: ${stderr}`);
  }
  
  log("INFO", `microsocks started on port ${port}`);
  return proc.pid;
}

async function setupPortForward(port: number, nsIndex: number): Promise<void> {
  const targetIp = `10.200.${nsIndex}.2`;
  
  spawnSync([
    "sudo", "iptables", "-t", "nat", "-A", "PREROUTING",
    "-p", "tcp", "--dport", port.toString(),
    "-j", "DNAT", "--to-destination", `${targetIp}:${port}`,
  ]);
  
  spawnSync([
    "sudo", "iptables", "-t", "nat", "-A", "OUTPUT",
    "-p", "tcp", "-d", "127.0.0.1", "--dport", port.toString(),
    "-j", "DNAT", "--to-destination", `${targetIp}:${port}`,
  ]);
  
  log("INFO", `Port forwarding set up: localhost:${port} -> ${targetIp}:${port}`);
}

export async function startProxy(slug: string): Promise<{ port: number; vpn: VpnConfig }> {
  log("INFO", `Starting proxy for slug: "${slug}"`);
  
  let vpn: VpnConfig | null;
  let usedRandom = false;
  
  if (slug === "random") {
    const randomState = await loadRandomState();
    const now = Date.now();
    
    if (randomState && randomState.expiresAt > now) {
      vpn = await resolveVpn(randomState.slug);
      if (vpn) {
        log("INFO", `Using cached random VPN: ${vpn.displayName}`);
      }
    }
    
    if (!vpn) {
      vpn = await getRandomVpn();
      if (vpn) {
        await saveRandomState({
          slug: vpn.slug,
          expiresAt: now + RANDOM_ROTATION * 1000,
        });
        log("INFO", `Selected new random VPN: ${vpn.displayName}`);
      }
    }
    usedRandom = true;
  } else {
    vpn = await resolveVpn(slug);
    
    if (!vpn) {
      log("WARN", `VPN "${slug}" not found, falling back to random`);
      vpn = await getRandomVpn();
      usedRandom = true;
      
      if (vpn) {
        spawnSync([
          "notify-send", "-u", "warning",
          "VPN Proxy",
          `VPN "${slug}" not found. Using random: ${vpn.displayName}`,
        ]);
      }
    }
  }
  
  if (!vpn) {
    throw new Error("No VPN available");
  }
  
  const state = await loadState();
  
  const existingPort = state.slugToPort[vpn.slug];
  if (existingPort) {
    log("INFO", `Proxy already running for ${vpn.displayName} on port ${existingPort}`);
    state.lastUsed[existingPort] = Date.now();
    await saveState(state);
    return { port: existingPort, vpn };
  }
  
  const port = findAvailablePort(state);
  if (!port) {
    throw new Error("No available ports in range");
  }
  
  const nsIndex = port - PORT_START;
  
  try {
    const nsName = await createNamespace(port, vpn);
    
    const openvpnPid = await startOpenVPN(nsName, vpn);
    
    const tunnelUp = await waitForTunnel(nsName);
    if (!tunnelUp) {
      throw new Error("VPN tunnel failed to establish");
    }
    
    const microsocksPid = await startMicrosocks(nsName, port, nsIndex);
    
    await setupPortForward(port, nsIndex);
    
    state.slugToPort[vpn.slug] = port;
    state.portToSlug[port] = vpn.slug;
    state.portToNs[port] = nsName;
    state.lastUsed[port] = Date.now();
    state.pids[port] = { openvpn: openvpnPid, microsocks: microsocksPid };
    await saveState(state);
    
    log("INFO", `Proxy started: ${vpn.displayName} on port ${port}`);
    return { port, vpn };
    
  } catch (error) {
    log("ERROR", `Failed to start proxy: ${error}`);
    const nsName = `vpn-proxy-${nsIndex}`;
    await destroyNamespace(nsName);
    throw error;
  }
}

export async function stopProxy(slug: string): Promise<void> {
  log("INFO", `Stopping proxy for slug: "${slug}"`);
  
  const state = await loadState();
  const port = state.slugToPort[slug];
  
  if (!port) {
    log("WARN", `No active proxy found for slug: ${slug}`);
    return;
  }
  
  await stopProxyByPort(port, state);
}

async function stopProxyByPort(port: number, state: ProxyState): Promise<void> {
  const slug = state.portToSlug[port];
  const nsName = state.portToNs[port];
  const nsIndex = port - PORT_START;
  
  log("INFO", `Stopping proxy on port ${port} (${slug})`);
  
  spawnSync([
    "sudo", "iptables", "-t", "nat", "-D", "PREROUTING",
    "-p", "tcp", "--dport", port.toString(),
    "-j", "DNAT", "--to-destination", `10.200.${nsIndex}.2:${port}`,
  ]);
  
  spawnSync([
    "sudo", "iptables", "-t", "nat", "-D", "OUTPUT",
    "-p", "tcp", "-d", "127.0.0.1", "--dport", port.toString(),
    "-j", "DNAT", "--to-destination", `10.200.${nsIndex}.2:${port}`,
  ]);
  
  if (nsName) {
    await destroyNamespace(nsName);
  }
  
  delete state.slugToPort[slug];
  delete state.portToSlug[port];
  delete state.portToNs[port];
  delete state.lastUsed[port];
  delete state.pids[port];
  await saveState(state);
  
  log("INFO", `Proxy stopped on port ${port}`);
}

export async function getProxyPort(slug: string): Promise<number | null> {
  const state = await loadState();
  const port = state.slugToPort[slug];
  
  if (port) {
    state.lastUsed[port] = Date.now();
    await saveState(state);
  }
  
  return port || null;
}

export async function listProxies(): Promise<Array<{ slug: string; port: number; lastUsed: number }>> {
  const state = await loadState();
  return Object.entries(state.slugToPort).map(([slug, port]) => ({
    slug,
    port,
    lastUsed: state.lastUsed[port] || 0,
  }));
}

export async function cleanupIdleProxies(): Promise<number> {
  const state = await loadState();
  const now = Date.now();
  const threshold = now - IDLE_TIMEOUT * 1000;
  let cleaned = 0;
  
  for (const [portStr, lastUsed] of Object.entries(state.lastUsed)) {
    const port = parseInt(portStr, 10);
    if (lastUsed < threshold) {
      const slug = state.portToSlug[port];
      log("INFO", `Cleaning up idle proxy: ${slug} (port ${port})`);
      await stopProxyByPort(port, state);
      cleaned++;
    }
  }
  
  return cleaned;
}

export async function rotateRandom(): Promise<void> {
  const randomState = await loadRandomState();
  if (!randomState) return;
  
  const now = Date.now();
  if (randomState.expiresAt <= now) {
    const state = await loadState();
    const currentPort = state.slugToPort[randomState.slug];
    
    if (currentPort) {
      log("INFO", "Rotating random VPN");
      await stopProxyByPort(currentPort, state);
      
      const newVpn = await getRandomVpn();
      if (newVpn && newVpn.slug !== randomState.slug) {
        await saveRandomState({
          slug: newVpn.slug,
          expiresAt: now + RANDOM_ROTATION * 1000,
        });
        log("INFO", `New random VPN: ${newVpn.displayName}`);
      }
    }
  }
}

export async function stopAllProxies(): Promise<void> {
  log("INFO", "Stopping all proxies");
  runNetnsScript(["cleanup-all"]);
  
  await unlink(STATE_FILE).catch(() => {});
  await unlink(RANDOM_FILE).catch(() => {});
  
  log("INFO", "All proxies stopped");
}

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  const command = args[0];

  switch (command) {
    case "start": {
      const slug = args.slice(1).join(" ");
      if (!slug) {
        console.error("Usage: proxy-manager start <slug|random>");
        process.exit(1);
      }
      try {
        const { port, vpn } = await startProxy(slug);
        console.log(JSON.stringify({ port, slug: vpn.slug, displayName: vpn.displayName }));
      } catch (error) {
        console.error(`Error: ${error}`);
        process.exit(1);
      }
      break;
    }

    case "stop": {
      const slug = args.slice(1).join(" ");
      if (!slug) {
        console.error("Usage: proxy-manager stop <slug>");
        process.exit(1);
      }
      await stopProxy(slug);
      console.log("Stopped");
      break;
    }

    case "stop-all": {
      await stopAllProxies();
      console.log("All proxies stopped");
      break;
    }

    case "get": {
      const slug = args.slice(1).join(" ");
      if (!slug) {
        console.error("Usage: proxy-manager get <slug>");
        process.exit(1);
      }
      const port = await getProxyPort(slug);
      if (port) {
        console.log(`socks5://127.0.0.1:${port}`);
      } else {
        console.log("not-running");
      }
      break;
    }

    case "list": {
      const proxies = await listProxies();
      if (proxies.length === 0) {
        console.log("No active proxies");
      } else {
        for (const p of proxies) {
          const idle = Math.floor((Date.now() - p.lastUsed) / 1000);
          console.log(`${p.port}\t${p.slug}\t(idle: ${idle}s)`);
        }
      }
      break;
    }

    case "cleanup": {
      const cleaned = await cleanupIdleProxies();
      console.log(`Cleaned up ${cleaned} idle proxies`);
      break;
    }

    case "rotate-random": {
      await rotateRandom();
      console.log("Random rotation checked");
      break;
    }

    case "status": {
      const proxies = await listProxies();
      const randomState = await loadRandomState();
      console.log(JSON.stringify({ proxies, random: randomState }, null, 2));
      break;
    }

    default:
      console.log(`VPN Proxy Manager - SOCKS5 Proxy Lifecycle Management

Usage:
  proxy-manager start <slug|random>   Start proxy for VPN (or random)
  proxy-manager stop <slug>           Stop specific proxy
  proxy-manager stop-all              Stop all proxies
  proxy-manager get <slug>            Get proxy URL if running
  proxy-manager list                  List active proxies
  proxy-manager cleanup               Clean up idle proxies
  proxy-manager rotate-random         Check/perform random rotation
  proxy-manager status                Full status in JSON

Environment:
  VPN_PROXY_PORT_START      First port (default: 10800)
  VPN_PROXY_PORT_END        Last port (default: 10899)
  VPN_PROXY_IDLE_TIMEOUT    Idle timeout in seconds (default: 300)
  VPN_PROXY_RANDOM_ROTATION Random rotation interval (default: 300)
`);
  }
}

if (import.meta.main) {
  main().catch((error) => {
    log("ERROR", `Fatal error: ${error}`);
    process.exit(1);
  });
}
