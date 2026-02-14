#!/usr/bin/env bun
/**
 * VPN HTTP CONNECT Proxy Server
 *
 * Architecture:
 * ┌─────────────┐     ┌──────────────────┐     ┌─────────────────┐
 * │ Client App  │────▶│ HTTP CONNECT     │────▶│ Network Namespace│
 * │ (curl, etc) │     │ Proxy (:10801)   │     │ (vpn-proxy-N)   │
 * └─────────────┘     └──────────────────┘     └────────┬────────┘
 *                                                       │
 *                     Proxy-Authorization:              ▼
 *                     Basic <base64(vpn:pass)>     ┌─────────┐
 *                     OR no auth = random          │ OpenVPN │
 *                                                  │ Tunnel  │
 *                                                  └────┬────┘
 *                                                       ▼
 *                                                  Internet
 *
 * This implements HTTP CONNECT tunneling (RFC 7231 §4.3.6) which is used
 * for HTTPS proxying. The proxy establishes a TCP tunnel to the target
 * and then becomes a transparent pipe.
 *
 * Authentication:
 * - Proxy-Authorization: Basic <base64(username:password)>
 *   - username = VPN slug (e.g., "AirVPN AT Vienna")
 *   - password = ignored (can be empty)
 * - No auth header = random VPN selection
 *
 * Security Model:
 * - Same as SOCKS5: isolated network namespaces with kill-switch
 * - Only CONNECT method is supported (no plain HTTP proxying)
 * - Tunnel is transparent after establishment
 */

import { createServer, createConnection, type Socket } from "net";
import {
  log,
  CONFIG,
  ensureStateDir,
  loadState,
  getOrCreateNamespace,
  resolveSlugFromUsername,
  getStatus,
  stopAllProxies,
  forceRotateRandom,
} from "./shared";

// ============================================================================
// HTTP Parsing Helpers
// ============================================================================

/**
 * Parse the first line of an HTTP request
 * Returns: { method, target, version } or null if invalid
 */
function parseRequestLine(
  line: string,
): { method: string; target: string; version: string } | null {
  const parts = line.split(" ");
  if (parts.length !== 3) return null;
  return {
    method: parts[0]!,
    target: parts[1]!,
    version: parts[2]!,
  };
}

/**
 * Parse HTTP headers from request data
 * Returns a Map of header names (lowercase) to values
 */
function parseHeaders(lines: string[]): Map<string, string> {
  const headers = new Map<string, string>();
  for (const line of lines) {
    const colonIdx = line.indexOf(":");
    if (colonIdx > 0) {
      const name = line.substring(0, colonIdx).toLowerCase().trim();
      const value = line.substring(colonIdx + 1).trim();
      headers.set(name, value);
    }
  }
  return headers;
}

/**
 * Parse Basic authentication header
 * Returns username or null if not present/invalid
 */
function parseProxyAuth(authHeader: string | undefined): string | null {
  if (!authHeader) return null;

  // Format: "Basic <base64(username:password)>"
  const parts = authHeader.split(" ");
  if (parts.length !== 2 || parts[0]?.toLowerCase() !== "basic") {
    return null;
  }

  try {
    const decoded = Buffer.from(parts[1]!, "base64").toString("utf-8");
    const colonIdx = decoded.indexOf(":");
    if (colonIdx === -1) {
      // No colon - treat entire string as username
      return decoded;
    }
    // Username is everything before the first colon
    return decoded.substring(0, colonIdx);
  } catch {
    return null;
  }
}

/**
 * Parse host:port from CONNECT target
 * Returns { host, port } or null if invalid
 */
function parseConnectTarget(
  target: string,
): { host: string; port: number } | null {
  const lastColon = target.lastIndexOf(":");
  if (lastColon === -1) {
    // No port specified - default to 443 for HTTPS
    return { host: target, port: 443 };
  }

  const host = target.substring(0, lastColon);
  const portStr = target.substring(lastColon + 1);
  const port = parseInt(portStr, 10);

  if (isNaN(port) || port < 1 || port > 65535) {
    return null;
  }

  // Handle IPv6 addresses in brackets: [::1]:443
  if (host.startsWith("[") && host.endsWith("]")) {
    return { host: host.slice(1, -1), port };
  }

  return { host, port };
}

// ============================================================================
// Connection Handling
// ============================================================================

/**
 * Handle incoming HTTP CONNECT request
 */
async function handleConnection(clientSocket: Socket): Promise<void> {
  let buffer = Buffer.alloc(0);

  const onData = async (chunk: Buffer) => {
    buffer = Buffer.concat([buffer, chunk]);

    // Look for end of HTTP headers (double CRLF)
    const headerEnd = buffer.indexOf("\r\n\r\n");
    if (headerEnd === -1) {
      // Headers not complete yet - wait for more data
      if (buffer.length > 8192) {
        // Headers too large - reject
        clientSocket.write(
          "HTTP/1.1 431 Request Header Fields Too Large\r\n\r\n",
        );
        clientSocket.end();
      }
      return;
    }

    // Remove data listener - we have complete headers
    clientSocket.off("data", onData);

    const headerData = buffer.subarray(0, headerEnd).toString("utf-8");
    const lines = headerData.split("\r\n");

    if (lines.length === 0) {
      clientSocket.write("HTTP/1.1 400 Bad Request\r\n\r\n");
      clientSocket.end();
      return;
    }

    // Parse request line
    const requestLine = parseRequestLine(lines[0]!);
    if (!requestLine) {
      clientSocket.write("HTTP/1.1 400 Bad Request\r\n\r\n");
      clientSocket.end();
      return;
    }

    // Only support CONNECT method
    if (requestLine.method !== "CONNECT") {
      log("WARN", `Unsupported method: ${requestLine.method}`, "http");
      clientSocket.write(
        "HTTP/1.1 405 Method Not Allowed\r\n" +
          "Allow: CONNECT\r\n" +
          "Content-Type: text/plain\r\n" +
          "\r\n" +
          "Only CONNECT method is supported. Use this proxy for HTTPS tunneling.\n",
      );
      clientSocket.end();
      return;
    }

    // Parse headers
    const headers = parseHeaders(lines.slice(1));

    // Parse target host:port
    const target = parseConnectTarget(requestLine.target);
    if (!target) {
      clientSocket.write("HTTP/1.1 400 Bad Request\r\n\r\n");
      clientSocket.end();
      return;
    }

    // Extract username from Proxy-Authorization header
    const authHeader = headers.get("proxy-authorization");

    // No auth header = random VPN (don't challenge with 407)
    // This allows simple usage: curl -x http://127.0.0.1:10801 https://example.com
    // Browsers that need specific VPN selection can use Proxy-Authorization header
    const username = parseProxyAuth(authHeader) || "";

    log(
      "DEBUG",
      `CONNECT request: ${username || "random"}@${target.host}:${target.port}`,
      "http",
    );

    try {
      // Resolve VPN and get/create namespace
      const state = await loadState();
      const slug = await resolveSlugFromUsername(username, state);
      const nsInfo = await getOrCreateNamespace(slug, state);

      // Connect to target via namespace's SOCKS5 proxy
      await tunnelViaNamespace(clientSocket, nsInfo, target.host, target.port);
    } catch (error) {
      log("ERROR", `Connection failed: ${error}`, "http");
      clientSocket.write(
        "HTTP/1.1 502 Bad Gateway\r\n" +
          "Content-Type: text/plain\r\n" +
          "\r\n" +
          `VPN connection failed: ${error}\n`,
      );
      clientSocket.end();
    }
  };

  clientSocket.on("data", onData);

  clientSocket.on("error", (err) => {
    log("DEBUG", `Client socket error: ${err.message}`, "http");
  });
}

/**
 * Establish tunnel to target host via namespace's SOCKS5 proxy
 */
async function tunnelViaNamespace(
  clientSocket: Socket,
  nsInfo: { nsIp: string; socksPort: number; vpnDisplayName: string },
  targetHost: string,
  targetPort: number,
): Promise<void> {
  return new Promise((resolve, reject) => {
    // Connect to microsocks inside the namespace
    const proxySocket = createConnection(
      { host: nsInfo.nsIp, port: nsInfo.socksPort },
      () => {
        // Send SOCKS5 handshake (no auth)
        proxySocket.write(Buffer.from([0x05, 0x01, 0x00]));
      },
    );

    proxySocket.once("data", (handshakeReply: Buffer) => {
      if (handshakeReply[0] !== 0x05 || handshakeReply[1] !== 0x00) {
        reject(new Error("SOCKS5 handshake failed"));
        proxySocket.destroy();
        return;
      }

      // Send SOCKS5 CONNECT request
      const hostBytes = Buffer.from(targetHost, "utf-8");
      const request = Buffer.alloc(4 + 1 + hostBytes.length + 2);
      request[0] = 0x05; // Version
      request[1] = 0x01; // CONNECT
      request[2] = 0x00; // Reserved
      request[3] = 0x03; // Domain name
      request[4] = hostBytes.length;
      hostBytes.copy(request, 5);
      request.writeUInt16BE(targetPort, 5 + hostBytes.length);

      proxySocket.write(request);

      proxySocket.once("data", (connectReply: Buffer) => {
        if (connectReply[1] !== 0x00) {
          // SOCKS5 connection failed
          const errorCodes: Record<number, string> = {
            0x01: "General SOCKS server failure",
            0x02: "Connection not allowed by ruleset",
            0x03: "Network unreachable",
            0x04: "Host unreachable",
            0x05: "Connection refused",
            0x06: "TTL expired",
            0x07: "Command not supported",
            0x08: "Address type not supported",
          };
          const errorMsg = errorCodes[connectReply[1]!] || "Unknown error";
          reject(new Error(`SOCKS5: ${errorMsg}`));
          proxySocket.destroy();
          return;
        }

        // Connection established - send success to client
        clientSocket.write(
          "HTTP/1.1 200 Connection Established\r\n" +
            `Proxy-Agent: VPN-HTTP-Proxy (${nsInfo.vpnDisplayName})\r\n` +
            "\r\n",
        );

        // Bidirectional pipe
        clientSocket.pipe(proxySocket);
        proxySocket.pipe(clientSocket);

        resolve();
      });
    });

    proxySocket.on("error", (err) => {
      log("ERROR", `Proxy socket error: ${err.message}`, "http");
      clientSocket.destroy();
      reject(err);
    });

    clientSocket.on("error", () => {
      proxySocket.destroy();
    });

    clientSocket.on("close", () => {
      proxySocket.destroy();
    });

    proxySocket.on("close", () => {
      clientSocket.destroy();
    });
  });
}

// ============================================================================
// Server Lifecycle
// ============================================================================

async function startServer(): Promise<void> {
  await ensureStateDir();
  // Note: Don't cleanup stale state here - let socks5-proxy do it
  // Both proxies share the same state

  const server = createServer((socket) => {
    handleConnection(socket);
  });

  server.listen(CONFIG.HTTP_PORT, CONFIG.BIND_ADDRESS, () => {
    log(
      "INFO",
      `HTTP CONNECT proxy listening on ${CONFIG.BIND_ADDRESS}:${CONFIG.HTTP_PORT}`,
      "http",
    );
  });

  server.on("error", (err) => {
    log("ERROR", `Server error: ${err}`, "http");
    process.exit(1);
  });

  process.on("SIGTERM", async () => {
    log("INFO", "Shutting down...", "http");
    server.close();
    process.exit(0);
  });

  process.on("SIGINT", async () => {
    log("INFO", "Shutting down...", "http");
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
    console.log(`VPN HTTP CONNECT Proxy - Routes HTTPS traffic through VPNs

Usage:
  http-proxy [command]

Commands:
  serve         Start the HTTP CONNECT proxy server (default if no command)
  status        Show active VPN proxies and their idle times
  stop-all      Stop all VPN proxies and clean up namespaces
  rotate-random Force rotate the random VPN immediately

Options:
  -h, --help  Show this help message

Environment:
  VPN_DIR                    VPN configs directory (default: ~/Shared/VPNs)
  VPN_HTTP_PROXY_PORT        HTTP CONNECT listening port (default: 10801)
  VPN_PROXY_BIND_ADDRESS     Bind address: 127.0.0.1 (default) or 0.0.0.0 for LAN
  VPN_PROXY_IDLE_TIMEOUT     Idle cleanup timeout in seconds (default: 300)
  VPN_PROXY_RANDOM_ROTATION  Random VPN rotation interval (default: 300)
  VPN_PROXY_NOTIFY_ROTATION  Show notification on random rotation (default: 0)

Authentication:
  VPN selection via Proxy-Authorization header:
    Proxy-Authorization: Basic <base64(username:password)>
  
  Where username is the VPN name (e.g., "AirVPN AT Vienna").
  Password is ignored and can be empty.
  
  No auth header = random VPN selection.

Examples:
  http-proxy serve                   # Start the proxy server
  http-proxy status                  # Check active VPNs
  
  # Use with curl (VPN name via --proxy-user)
  curl --proxy "http://127.0.0.1:10801" \\
       --proxy-user "AirVPN AT Vienna:" \\
       https://api.ipify.org
  
  # Random VPN (no auth)
  curl --proxy "http://127.0.0.1:10801" https://api.ipify.org
  
  # URL-encoded username in proxy URL
  curl -x "http://AirVPN%20AT%20Vienna@127.0.0.1:10801" https://api.ipify.org
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
          `Unknown command: ${command}\nRun 'http-proxy --help' for usage.`,
        );
        process.exit(1);
      }
      await startServer();
      break;
  }
}

if (import.meta.main) {
  main().catch((error) => {
    log("ERROR", `Fatal: ${error}`, "http");
    process.exit(1);
  });
}
