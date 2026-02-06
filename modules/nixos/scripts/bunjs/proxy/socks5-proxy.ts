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

import { createServer, createConnection, type Socket } from "net";
import {
  log,
  CONFIG,
  ensureStateDir,
  loadState,
  getOrCreateNamespace,
  resolveSlugFromUsername,
  cleanupStaleState,
  getStatus,
  stopAllProxies,
  forceRotateRandom,
  cleanupIdleProxies,
  rotateRandom,
  type NamespaceInfo,
} from "./shared";

// Re-export for cleanup daemon
export { cleanupIdleProxies, rotateRandom };

// ============================================================================
// SOCKS5 Protocol Helpers
// ============================================================================

/**
 * Parse SOCKS5 username/password authentication (RFC 1929)
 *
 * Format:
 * +----+------+----------+------+----------+
 * |VER | ULEN |  UNAME   | PLEN |  PASSWD  |
 * +----+------+----------+------+----------+
 * | 1  |  1   | 1 to 255 |  1   | 1 to 255 |
 * +----+------+----------+------+----------+
 */
function parseSocks5Auth(
  data: Buffer,
): { username: string; password: string } | null {
  if (data.length < 5) return null;
  const version = data[0];
  if (version !== 0x01) return null; // Auth sub-negotiation version

  const ulen = data[1]!;
  if (data.length < 2 + ulen + 1) return null;

  const username = data.subarray(2, 2 + ulen).toString("utf-8");
  const plen = data[2 + ulen]!;
  if (data.length < 3 + ulen + plen) return null;

  const password = data.subarray(3 + ulen, 3 + ulen + plen).toString("utf-8");
  return { username, password };
}

/**
 * Forward traffic to the SOCKS5 proxy running inside the namespace
 * The namespace runs microsocks bound to its veth IP
 */
function forwardToNamespaceSocks(
  clientSocket: Socket,
  nsInfo: NamespaceInfo,
  socks5Request: Buffer,
): void {
  const upstreamSocket = createConnection(
    { host: nsInfo.nsIp, port: nsInfo.socksPort },
    () => {
      // Send SOCKS5 handshake to upstream (no auth)
      upstreamSocket.write(Buffer.from([0x05, 0x01, 0x00]));
    },
  );

  upstreamSocket.once("data", (handshakeReply: Buffer) => {
    if (handshakeReply[0] !== 0x05 || handshakeReply[1] !== 0x00) {
      log("ERROR", "Upstream SOCKS5 handshake failed", "socks5");
      clientSocket.end();
      upstreamSocket.end();
      return;
    }

    // Forward the original CONNECT request
    upstreamSocket.write(socks5Request);

    upstreamSocket.once("data", (connectReply: Buffer) => {
      clientSocket.write(connectReply);

      if (connectReply[1] !== 0x00) {
        // Connection failed
        clientSocket.end();
        upstreamSocket.end();
        return;
      }

      // Bidirectional pipe for data transfer
      clientSocket.pipe(upstreamSocket);
      upstreamSocket.pipe(clientSocket);
    });
  });

  upstreamSocket.on("error", (err) => {
    log("ERROR", `Upstream error: ${err.message}`, "socks5");
    clientSocket.destroy();
  });

  clientSocket.on("error", () => {
    upstreamSocket.destroy();
  });

  clientSocket.on("close", () => {
    upstreamSocket.destroy();
  });

  upstreamSocket.on("close", () => {
    clientSocket.destroy();
  });
}

// ============================================================================
// Connection Handling
// ============================================================================

/**
 * Handle incoming SOCKS5 connection
 */
async function handleConnection(clientSocket: Socket): Promise<void> {
  let username = "";

  clientSocket.once("data", async (data: Buffer) => {
    try {
      // SOCKS5 version check
      if (data[0] !== 0x05) {
        clientSocket.end();
        return;
      }

      const nmethods = data[1]!;
      const methods = data.subarray(2, 2 + nmethods);
      const supportsAuth = methods.includes(0x02); // Username/password

      if (supportsAuth) {
        // Request username/password auth
        clientSocket.write(Buffer.from([0x05, 0x02]));

        clientSocket.once("data", async (authData: Buffer) => {
          const auth = parseSocks5Auth(authData);
          if (auth) {
            username = auth.username;
          }
          // Accept auth (we don't validate password, just use username for VPN selection)
          clientSocket.write(Buffer.from([0x01, 0x00]));
          await handleSocks5Request(clientSocket, username);
        });
      } else {
        // No auth - use random VPN
        clientSocket.write(Buffer.from([0x05, 0x00]));
        await handleSocks5Request(clientSocket, "");
      }
    } catch (error) {
      log("ERROR", `Connection error: ${error}`, "socks5");
      clientSocket.end();
    }
  });
}

/**
 * Handle SOCKS5 CONNECT request after authentication
 */
async function handleSocks5Request(
  clientSocket: Socket,
  username: string,
): Promise<void> {
  clientSocket.once("data", async (data: Buffer) => {
    try {
      const state = await loadState();

      // Validate SOCKS5 CONNECT request
      if (data[0] !== 0x05 || data[1] !== 0x01) {
        // Not a CONNECT command - reply with "Command not supported"
        clientSocket.write(
          Buffer.from([0x05, 0x07, 0x00, 0x01, 0, 0, 0, 0, 0, 0]),
        );
        clientSocket.end();
        return;
      }

      // Parse address type
      const atyp = data[3];
      let targetHost: string;
      let addrEnd: number;

      if (atyp === 0x01) {
        // IPv4: 4 bytes
        targetHost = `${data[4]}.${data[5]}.${data[6]}.${data[7]}`;
        addrEnd = 8;
      } else if (atyp === 0x03) {
        // Domain name: 1 byte length + name
        const domainLen = data[4]!;
        targetHost = data.subarray(5, 5 + domainLen).toString("utf-8");
        addrEnd = 5 + domainLen;
      } else if (atyp === 0x04) {
        // IPv6 - not supported
        clientSocket.write(
          Buffer.from([0x05, 0x08, 0x00, 0x01, 0, 0, 0, 0, 0, 0]),
        );
        clientSocket.end();
        return;
      } else {
        clientSocket.end();
        return;
      }

      const targetPort = (data[addrEnd]! << 8) | data[addrEnd + 1]!;

      log(
        "DEBUG",
        `SOCKS5 request: ${username || "random"}@${targetHost}:${targetPort}`,
        "socks5",
      );

      // Resolve VPN and get/create namespace
      const slug = await resolveSlugFromUsername(username, state);
      const nsInfo = await getOrCreateNamespace(slug, state);

      // Forward to namespace's SOCKS5 proxy
      forwardToNamespaceSocks(clientSocket, nsInfo, data);
    } catch (error) {
      log("ERROR", `Request error: ${error}`, "socks5");
      // General SOCKS5 failure reply
      clientSocket.write(
        Buffer.from([0x05, 0x01, 0x00, 0x01, 0, 0, 0, 0, 0, 0]),
      );
      clientSocket.end();
    }
  });
}

// ============================================================================
// Server Lifecycle
// ============================================================================

async function startServer(): Promise<void> {
  await ensureStateDir();
  await cleanupStaleState();

  const server = createServer((socket) => {
    handleConnection(socket);
  });

  server.listen(CONFIG.SOCKS5_PORT, CONFIG.BIND_ADDRESS, () => {
    log(
      "INFO",
      `SOCKS5 proxy listening on ${CONFIG.BIND_ADDRESS}:${CONFIG.SOCKS5_PORT}`,
      "socks5",
    );
  });

  server.on("error", (err) => {
    log("ERROR", `Server error: ${err}`, "socks5");
    process.exit(1);
  });

  process.on("SIGTERM", async () => {
    log("INFO", "Shutting down...", "socks5");
    server.close();
    process.exit(0);
  });

  process.on("SIGINT", async () => {
    log("INFO", "Shutting down...", "socks5");
    server.close();
    process.exit(0);
  });
}

// ============================================================================
// CLI Interface
// ============================================================================

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  const command = args[0];

  if (args.includes("--help") || args.includes("-h")) {
    console.log(`VPN SOCKS5 Proxy - Routes traffic through VPNs via username authentication

Usage:
  vpn-proxy [command]

Commands:
  serve         Start the SOCKS5 proxy server (default if no command)
  status        Show active VPN proxies and their idle times
  stop-all      Stop all VPN proxies and clean up namespaces
  rotate-random Force rotate the random VPN immediately

Options:
  -h, --help  Show this help message

Environment:
  VPN_DIR                    VPN configs directory (default: ~/Shared/VPNs)
  VPN_PROXY_PORT             SOCKS5 listening port (default: 10800)
  VPN_HTTP_PROXY_PORT        HTTP CONNECT listening port (default: 10801)
  VPN_PROXY_BIND_ADDRESS     Bind address: 127.0.0.1 (default) or 0.0.0.0 for LAN
  VPN_PROXY_IDLE_TIMEOUT     Idle cleanup timeout in seconds (default: 300)
  VPN_PROXY_RANDOM_ROTATION  Random VPN rotation interval (default: 300)
  VPN_PROXY_NOTIFY_ROTATION  Show notification on random rotation (default: 0)

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
    case "rotate-random":
      const rotatedTo = await forceRotateRandom();
      if (rotatedTo) {
        console.log(`Random VPN rotated to: ${rotatedTo}`);
      } else {
        console.log("No VPNs available for rotation");
        process.exit(1);
      }
      break;
    case "serve":
      await startServer();
      break;
    default:
      if (command && command !== "serve") {
        console.error(
          `Unknown command: ${command}\nRun 'vpn-proxy --help' for usage.`,
        );
        process.exit(1);
      }
      await startServer();
      break;
  }
}

if (import.meta.main) {
  main().catch((error) => {
    log("ERROR", `Fatal: ${error}`, "socks5");
    process.exit(1);
  });
}
