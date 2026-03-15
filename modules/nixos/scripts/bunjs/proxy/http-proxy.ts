#!/usr/bin/env bun

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
  recordTransfer,
} from "./shared";

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

function parseProxyAuth(authHeader: string | undefined): string | null {
  if (!authHeader) return null;

  const parts = authHeader.split(" ");
  if (parts.length !== 2 || parts[0]?.toLowerCase() !== "basic") {
    return null;
  }

  try {
    const decoded = Buffer.from(parts[1]!, "base64").toString("utf-8");
    const colonIdx = decoded.indexOf(":");
    if (colonIdx === -1) {
      return decoded;
    }
    return decoded.substring(0, colonIdx);
  } catch {
    return null;
  }
}

function parseConnectTarget(
  target: string,
): { host: string; port: number } | null {
  const lastColon = target.lastIndexOf(":");
  if (lastColon === -1) {
    return { host: target, port: 443 };
  }

  const host = target.substring(0, lastColon);
  const portStr = target.substring(lastColon + 1);
  const port = parseInt(portStr, 10);

  if (isNaN(port) || port < 1 || port > 65535) {
    return null;
  }

  if (host.startsWith("[") && host.endsWith("]")) {
    return { host: host.slice(1, -1), port };
  }

  return { host, port };
}

async function handleConnection(clientSocket: Socket): Promise<void> {
  let challengeSent = false;

  const processRequest = async () => {
    let buffer = Buffer.alloc(0);

    const onData = async (chunk: Buffer) => {
      buffer = Buffer.concat([buffer, chunk]);

      const headerEnd = buffer.indexOf("\r\n\r\n");
      if (headerEnd === -1) {
        if (buffer.length > 8192) {
          clientSocket.write(
            "HTTP/1.1 431 Request Header Fields Too Large\r\n\r\n",
          );
          clientSocket.end();
        }
        return;
      }

      clientSocket.off("data", onData);

      const headerData = buffer.subarray(0, headerEnd).toString("utf-8");
      const lines = headerData.split("\r\n");

      if (lines.length === 0) {
        clientSocket.write("HTTP/1.1 400 Bad Request\r\n\r\n");
        clientSocket.end();
        return;
      }

      const requestLine = parseRequestLine(lines[0]!);
      if (!requestLine) {
        clientSocket.write("HTTP/1.1 400 Bad Request\r\n\r\n");
        clientSocket.end();
        return;
      }

      const headers = parseHeaders(lines.slice(1));

      const authHeader = headers.get("proxy-authorization");
      const needsChallenge =
        requestLine.method === "CONNECT" && !authHeader && !challengeSent;

      if (needsChallenge) {
        challengeSent = true;
        clientSocket.write(
          "HTTP/1.1 407 Proxy Authentication Required\r\n" +
            "Proxy-Authenticate: Basic realm=\"VPN Proxy (Username=VPN Name or 'random')\"\r\n" +
            "Content-Length: 0\r\n" +
            "\r\n",
        );
        processRequest();
        return;
      }

      const username = parseProxyAuth(authHeader) || "";

      if (requestLine.method === "CONNECT") {
        const target = parseConnectTarget(requestLine.target);
        if (!target) {
          clientSocket.write("HTTP/1.1 400 Bad Request\r\n\r\n");
          clientSocket.end();
          return;
        }

        log(
          "DEBUG",
          `CONNECT request: ${username || "random"}@${target.host}:${target.port}`,
          "http",
        );

        try {
          const state = await loadState();
          const slug = await resolveSlugFromUsername(username, state);
          const nsInfo = await getOrCreateNamespace(slug, state);

          await tunnelViaNamespace(
            clientSocket,
            nsInfo,
            target.host,
            target.port,
            slug,
          );
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
        return;
      }

      let targetHost = "";
      let targetPort = 80;
      let path = "";

      if (requestLine.target.startsWith("http://")) {
        let targetUrl: URL;
        try {
          targetUrl = new URL(requestLine.target);
        } catch {
          clientSocket.write("HTTP/1.1 400 Bad Request\r\n\r\n");
          clientSocket.end();
          return;
        }

        if (targetUrl.protocol !== "http:") {
          clientSocket.write("HTTP/1.1 400 Bad Request\r\n\r\n");
          clientSocket.end();
          return;
        }

        targetHost = targetUrl.hostname;
        targetPort = targetUrl.port ? parseInt(targetUrl.port, 10) : 80;
        if (!targetHost || isNaN(targetPort)) {
          clientSocket.write("HTTP/1.1 400 Bad Request\r\n\r\n");
          clientSocket.end();
          return;
        }

        path = `${targetUrl.pathname || "/"}${targetUrl.search || ""}`;
      } else {
        const hostHeader = headers.get("host") || "";
        const hostParts = hostHeader.split(":");
        targetHost = hostParts[0] || "";
        targetPort = hostParts[1] ? parseInt(hostParts[1], 10) : 80;
        if (!targetHost || isNaN(targetPort)) {
          clientSocket.write("HTTP/1.1 400 Bad Request\r\n\r\n");
          clientSocket.end();
          return;
        }

        path = requestLine.target || "/";
      }
      const requestLineOut = `${requestLine.method} ${path} ${requestLine.version}`;
      headers.delete("proxy-authorization");
      headers.set(
        "host",
        targetPort !== 80 ? `${targetHost}:${targetPort}` : targetHost,
      );

      log(
        "DEBUG",
        `HTTP request: ${username || "random"}@${targetHost}:${targetPort}`,
        "http",
      );

      try {
        const state = await loadState();
        const slug = await resolveSlugFromUsername(username, state);
        const nsInfo = await getOrCreateNamespace(slug, state);

        await forwardHttpViaNamespace(
          clientSocket,
          nsInfo,
          targetHost,
          targetPort,
          slug,
          requestLineOut,
          headers,
          buffer.subarray(headerEnd + 4),
        );
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
    const onEnd = () => {
      if (buffer.length > 0 && buffer.indexOf("\r\n\r\n") === -1) {
        clientSocket.end("HTTP/1.1 400 Bad Request\r\n\r\n");
      }
    };
    clientSocket.once("end", onEnd);
  };

  processRequest();

  clientSocket.on("error", (err) => {
    log("DEBUG", `Client socket error: ${err.message}`, "http");
  });
}

async function tunnelViaNamespace(
  clientSocket: Socket,
  nsInfo: { nsIp: string; socksPort: number; vpnDisplayName: string },
  targetHost: string,
  targetPort: number,
  slug: string,
): Promise<void> {
  return new Promise((resolve, reject) => {
    let bytesIn = 0;
    let bytesOut = 0;

    const proxySocket = createConnection(
      { host: nsInfo.nsIp, port: nsInfo.socksPort },
      () => {
        proxySocket.write(Buffer.from([0x05, 0x01, 0x00]));
      },
    );

    proxySocket.once("data", (handshakeReply: Buffer) => {
      if (handshakeReply[0] !== 0x05 || handshakeReply[1] !== 0x00) {
        reject(new Error("SOCKS5 handshake failed"));
        proxySocket.destroy();
        return;
      }

      const hostBytes = Buffer.from(targetHost, "utf-8");
      const request = Buffer.alloc(4 + 1 + hostBytes.length + 2);
      request[0] = 0x05;
      request[1] = 0x01;
      request[2] = 0x00;
      request[3] = 0x03;
      request[4] = hostBytes.length;
      hostBytes.copy(request, 5);
      request.writeUInt16BE(targetPort, 5 + hostBytes.length);

      proxySocket.write(request);

      proxySocket.once("data", (connectReply: Buffer) => {
        if (connectReply[1] !== 0x00) {
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

        clientSocket.write(
          "HTTP/1.1 200 Connection Established\r\n" +
            `Proxy-Agent: VPN-HTTP-Proxy (${nsInfo.vpnDisplayName})\r\n` +
            "\r\n",
        );

        clientSocket.on("data", (chunk: Buffer) => {
          bytesOut += chunk.length;
          proxySocket.write(chunk);
        });
        proxySocket.on("data", (chunk: Buffer) => {
          bytesIn += chunk.length;
          clientSocket.write(chunk);
        });

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

    const onClose = () => {
      recordTransfer(slug, bytesIn, bytesOut).catch(() => {});
    };

    clientSocket.on("close", () => {
      onClose();
      proxySocket.destroy();
    });

    proxySocket.on("close", () => {
      clientSocket.destroy();
    });
  });
}

async function forwardHttpViaNamespace(
  clientSocket: Socket,
  nsInfo: { nsIp: string; socksPort: number; vpnDisplayName: string },
  targetHost: string,
  targetPort: number,
  slug: string,
  requestLine: string,
  headers: Map<string, string>,
  initialBody: Buffer,
): Promise<void> {
  return new Promise((resolve, reject) => {
    let bytesIn = 0;
    let bytesOut = 0;

    const proxySocket = createConnection(
      { host: nsInfo.nsIp, port: nsInfo.socksPort },
      () => {
        proxySocket.write(Buffer.from([0x05, 0x01, 0x00]));
      },
    );

    proxySocket.once("data", (handshakeReply: Buffer) => {
      if (handshakeReply[0] !== 0x05 || handshakeReply[1] !== 0x00) {
        reject(new Error("SOCKS5 handshake failed"));
        proxySocket.destroy();
        return;
      }

      const hostBytes = Buffer.from(targetHost, "utf-8");
      const request = Buffer.alloc(4 + 1 + hostBytes.length + 2);
      request[0] = 0x05;
      request[1] = 0x01;
      request[2] = 0x00;
      request[3] = 0x03;
      request[4] = hostBytes.length;
      hostBytes.copy(request, 5);
      request.writeUInt16BE(targetPort, 5 + hostBytes.length);

      proxySocket.write(request);

      proxySocket.once("data", (connectReply: Buffer) => {
        if (connectReply[1] !== 0x00) {
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

        headers.delete("proxy-connection");
        const headerLines = [requestLine];
        for (const [name, value] of headers) {
          headerLines.push(`${name}: ${value}`);
        }
        const headerPayload = `${headerLines.join("\r\n")}\r\n\r\n`;
        proxySocket.write(headerPayload);
        if (initialBody.length > 0) {
          proxySocket.write(initialBody);
        }

        clientSocket.on("data", (chunk: Buffer) => {
          bytesOut += chunk.length;
          proxySocket.write(chunk);
        });
        proxySocket.on("data", (chunk: Buffer) => {
          bytesIn += chunk.length;
          clientSocket.write(chunk);
        });

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

    const onClose = () => {
      recordTransfer(slug, bytesIn, bytesOut).catch(() => {});
    };

    clientSocket.on("close", () => {
      onClose();
      proxySocket.destroy();
    });

    proxySocket.on("close", () => {
      clientSocket.destroy();
    });
  });
}

async function startServer(): Promise<void> {
  await ensureStateDir();

  const server = createServer((socket) => {
    handleConnection(socket);
  });

  server.listen(CONFIG.HTTP_PORT, CONFIG.BIND_ADDRESS, () => {
    log(
      "INFO",
      `HTTP proxy listening on ${CONFIG.BIND_ADDRESS}:${CONFIG.HTTP_PORT}`,
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

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  const command = args[0];

  if (args.includes("--help") || args.includes("-h") || !command) {
    console.log(`Legacy HTTP Proxy - Deprecated (use sing-box)

Usage:
  http-proxy [command]

Commands:
  serve         Start the HTTP proxy server
  status        Show active VPN proxies and their idle times
  stop-all      Stop all VPN proxies and clean up namespaces
  rotate-random Force rotate the random VPN immediately
  tool          Launch tools TUI or CLI subcommands

Options:
  -h, --help  Show this help message

Environment:
  VPN_DIR                    VPN configs directory (default: ~/Shared/VPNs)
  VPN_HTTP_PROXY_PORT        HTTP proxy listening port (default: 10801)
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
    case "tool":
    case "tools":
      const { runTools } = await import("./cli-tools");
      await runTools(args.slice(1));
      break;
    default:
      console.error(
        `Unknown command: ${command || "none"}\nRun 'http-proxy --help' for usage.`,
      );
      process.exit(1);
  }
}

if (import.meta.main) {
  main().catch((error) => {
    log("ERROR", `Fatal: ${error}`, "http");
    process.exit(1);
  });
}
