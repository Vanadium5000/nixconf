import { listVpns, getRandomVpn } from "./vpn-resolver";
import { CONFIG } from "./shared";
import { spawn } from "bun";
import * as readline from "readline";

export async function runTools(args: string[]) {
  const subcommand = args[0];

  if (!subcommand) {
    await runTui();
    return;
  }

  switch (subcommand) {
    case "list-usernames": {
      const vpns = await listVpns();
      console.log(vpns.map((v) => v.slug).join("\n"));
      break;
    }
    case "list-socks5": {
      const vpns = await listVpns();
      vpns.forEach((v) =>
        console.log(`socks5h://${v.slug}@127.0.0.1:${CONFIG.SOCKS5_PORT}`),
      );
      break;
    }
    case "list-http": {
      const vpns = await listVpns();
      vpns.forEach((v) =>
        console.log(`http://${v.slug}:@127.0.0.1:${CONFIG.HTTP_PORT}`),
      );
      break;
    }
    case "random-username": {
      const v = await getRandomVpn();
      if (v) console.log(v.slug);
      break;
    }
    case "random-socks5": {
      const v = await getRandomVpn();
      if (v) console.log(`socks5h://${v.slug}@127.0.0.1:${CONFIG.SOCKS5_PORT}`);
      break;
    }
    case "random-http": {
      const v = await getRandomVpn();
      if (v) console.log(`http://${v.slug}:@127.0.0.1:${CONFIG.HTTP_PORT}`);
      break;
    }
    case "health": {
      const target = args[1];
      if (!target) {
        console.error("Usage: vpn-proxy tool health <username_or_proxy_url>");
        process.exit(1);
      }
      await runHealthCheck(target);
      break;
    }
    case "help":
    default:
      console.log(`VPN Proxy Tools

Usage:
  vpn-proxy tool                    Launch interactive TUI
  vpn-proxy tool list-usernames     List all VPN usernames
  vpn-proxy tool list-socks5        List all SOCKS5 proxy URLs
  vpn-proxy tool list-http          List all HTTP proxy URLs
  vpn-proxy tool random-username    Get a random VPN username
  vpn-proxy tool random-socks5      Get a random SOCKS5 proxy URL
  vpn-proxy tool random-http        Get a random HTTP proxy URL
  vpn-proxy tool health <target>    Health check a username or proxy URL
`);
  }
}

async function runHealthCheck(target: string) {
  let proxyUrl = target;

  // If it doesn't look like a URL, assume it's a username and use SOCKS5
  if (!target.includes("://")) {
    proxyUrl = `socks5h://${target}@127.0.0.1:${CONFIG.SOCKS5_PORT}`;
    console.log(`Assuming username, testing SOCKS5: ${proxyUrl}\n`);
  } else {
    console.log(`Testing Proxy: ${proxyUrl}\n`);
  }

  console.log("Fetching real IP info (no proxy)...");
  try {
    const real = await fetchIpInfo();
    console.log(`Real IP:      ${real.ip}`);
    console.log(`Location:     ${real.location}`);
    console.log(`ISP:          ${real.isp}`);
    console.log(`Latency:      ${real.latency}\n`);
  } catch (e: any) {
    console.error(`Failed to fetch real IP: ${e.message}\n`);
  }

  console.log("Fetching proxied IP info...");
  try {
    const proxied = await fetchIpInfo(proxyUrl);
    console.log(`Proxied IP:   ${proxied.ip}`);
    console.log(`Location:     ${proxied.location}`);
    console.log(`ISP:          ${proxied.isp}`);
    console.log(`Latency:      ${proxied.latency}`);
  } catch (e: any) {
    console.error(`Failed to fetch proxied IP: ${e.message}`);
    process.exit(1);
  }
}

async function fetchIpInfo(proxyUrl?: string) {
  const start = Date.now();

  const args = ["-s", "-m", "15", "http://ip-api.com/json/"];
  if (proxyUrl) {
    args.push("--proxy", proxyUrl);
  }

  const proc = spawn(["curl", ...args]);
  const text = await new Response(proc.stdout).text();
  const latency = Date.now() - start;

  if (proc.exitCode !== 0) {
    throw new Error(`cURL failed with exit code ${proc.exitCode}`);
  }

  try {
    const data = JSON.parse(text);
    if (data.status !== "success")
      throw new Error(data.message || "API failed");
    return {
      ip: data.query,
      location: `${data.city}, ${data.country}`,
      isp: data.isp,
      latency: `${latency}ms`,
    };
  } catch (e) {
    throw new Error("Failed to parse API response");
  }
}

async function runTui() {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  const question = (query: string): Promise<string> =>
    new Promise((resolve) => rl.question(query, resolve));

  console.clear();
  console.log("=== VPN Proxy Tools TUI ===\n");
  console.log("1. List VPN usernames");
  console.log("2. List SOCKS5 proxies");
  console.log("3. List HTTP proxies");
  console.log("4. Get random proxy");
  console.log("5. Health check VPN");
  console.log("0. Exit\n");

  const choice = await question("Select an option: ");

  switch (choice.trim()) {
    case "1": {
      const vpns = await listVpns();
      console.log("\n" + vpns.map((v) => v.slug).join("\n"));
      break;
    }
    case "2": {
      const vpns = await listVpns();
      console.log(
        "\n" +
          vpns
            .map((v) => `socks5h://${v.slug}@127.0.0.1:${CONFIG.SOCKS5_PORT}`)
            .join("\n"),
      );
      break;
    }
    case "3": {
      const vpns = await listVpns();
      console.log(
        "\n" +
          vpns
            .map((v) => `http://${v.slug}:@127.0.0.1:${CONFIG.HTTP_PORT}`)
            .join("\n"),
      );
      break;
    }
    case "4": {
      const v = await getRandomVpn();
      if (v) {
        console.log(`\nUsername: ${v.slug}`);
        console.log(
          `SOCKS5:   socks5h://${v.slug}@127.0.0.1:${CONFIG.SOCKS5_PORT}`,
        );
        console.log(
          `HTTP:     http://${v.slug}:@127.0.0.1:${CONFIG.HTTP_PORT}`,
        );
      }
      break;
    }
    case "5": {
      const vpns = await listVpns();
      console.log("\nAvailable VPNs:");
      vpns.slice(0, 10).forEach((v, i) => console.log(`${i + 1}. ${v.slug}`));
      console.log("... and more");

      const target = await question("\nEnter VPN username or full proxy URL: ");
      if (target) {
        console.log("");
        await runHealthCheck(target);
      }
      break;
    }
    case "0":
      rl.close();
      return;
    default:
      console.log("Invalid option");
  }

  rl.close();
}
