import { mkdir, writeFile } from "fs/promises";

type SingBoxConfig = {
  log: { level: string; timestamp: boolean };
  inbounds: Array<Record<string, unknown>>;
  outbounds: Array<Record<string, unknown>>;
  route: { rules: Array<Record<string, unknown>> };
};

async function writeConfig(): Promise<void> {
  const bindAddress = process.env.VPN_PROXY_BIND_ADDRESS || "0.0.0.0";
  const httpPort = parseInt(process.env.VPN_HTTP_PROXY_PORT || "10801", 10);

  const upstreamSocksPort = parseInt(process.env.VPN_PROXY_PORT || "10800", 10);

  const config: SingBoxConfig = {
    log: { level: "info", timestamp: true },
    inbounds: [
      {
        type: "http",
        tag: "http-in",
        listen: bindAddress,
        listen_port: httpPort,
      },
    ],
    outbounds: [
      {
        type: "socks",
        tag: "vpn-socks",
        server: "127.0.0.1",
        server_port: upstreamSocksPort,
        version: "5",
        network: "tcp",
      },
      { type: "direct", tag: "direct" },
    ],
    route: {
      rules: [
        {
          inbound: ["http-in"],
          outbound: "vpn-socks",
        },
      ],
    },
  };

  const configPath =
    process.env.VPN_PROXY_SINGBOX_CONFIG || "/var/lib/vpn-proxy/sing-box.json";
  await mkdir("/var/lib/vpn-proxy", { recursive: true });
  await writeFile(configPath, JSON.stringify(config, null, 2));
}

writeConfig().catch((error) => {
  console.error(`Failed to write sing-box config: ${error}`);
  process.exit(1);
});
