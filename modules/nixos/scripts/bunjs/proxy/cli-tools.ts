import { listVpns, getRandomVpn, resolveVpnByPattern } from "./vpn-resolver";
import { CONFIG, loadState } from "./shared";
import {
  loadSettings,
  saveSettings,
  getDefaultSettings,
  getDynamicIdleTimeout,
} from "./settings";
import {
  testSingleProxy,
  testAllProxies,
  loadTestResults,
  getFailedSlugs,
  isAutoTestDue,
} from "./proxy-tester";
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

    // ======================== Settings ========================

    case "settings": {
      const settingsCmd = args[1];
      switch (settingsCmd) {
        case "show": {
          const settings = await loadSettings();
          console.log(JSON.stringify(settings, null, 2));
          break;
        }
        case "set": {
          const key = args[2];
          const value = args[3];
          if (!key || value === undefined) {
            console.error("Usage: vpn-proxy tool settings set <key> <value>");
            console.error("  Keys use dot notation: testing.intervalHours 12");
            process.exit(1);
          }
          const settings = await loadSettings();
          setNestedValue(
            settings as unknown as Record<string, unknown>,
            key,
            parseCliValue(value),
          );
          await saveSettings(settings);
          console.log(`Set ${key} = ${value}`);
          break;
        }
        case "reset": {
          await saveSettings(getDefaultSettings());
          console.log("Settings reset to defaults");
          break;
        }
        case "timeout": {
          const count = parseInt(args[2] || "0", 10);
          const settings = await loadSettings();
          const timeout = getDynamicIdleTimeout(
            count,
            settings.idleTimeoutTiers,
          );
          console.log(
            `Active: ${count} → Idle timeout: ${timeout}s (${Math.floor(timeout / 60)}m ${timeout % 60}s)`,
          );
          break;
        }
        default:
          console.log(`Settings Management

Usage:
  vpn-proxy tool settings show                     Show current settings
  vpn-proxy tool settings set <key> <value>        Update a setting (dot notation)
  vpn-proxy tool settings reset                    Reset to defaults
  vpn-proxy tool settings timeout <active_count>   Show idle timeout for N active proxies
`);
      }
      break;
    }

    // ======================== Testing ========================

    case "test": {
      const testCmd = args[1];
      switch (testCmd) {
        case "single": {
          const slug = args[2];
          if (!slug) {
            console.error("Usage: vpn-proxy tool test single <slug>");
            process.exit(1);
          }
          const vpns = await listVpns();
          const vpn = vpns.find((v) => v.slug === slug);
          if (!vpn) {
            console.error(`VPN not found: ${slug}`);
            process.exit(1);
          }
          console.log(`Testing ${vpn.displayName}...`);
          const result = await testSingleProxy(vpn);
          const icon = result.success ? "✓" : "✗";
          console.log(
            `${icon} ${result.displayName}${result.success ? ` (${result.latencyMs}ms, IP: ${result.ip})` : ` — ${result.error}`}`,
          );
          break;
        }
        case "all": {
          await testAllProxies((completed, total, result) => {
            const icon = result.success ? "✓" : "✗";
            console.log(
              `[${completed}/${total}] ${icon} ${result.displayName}${result.success ? ` (${result.latencyMs}ms)` : ` — ${result.error}`}`,
            );
          });
          break;
        }
        case "results": {
          const state = await loadTestResults();
          console.log(JSON.stringify(state, null, 2));
          break;
        }
        case "failed": {
          const failed = await getFailedSlugs();
          if (failed.size === 0) {
            console.log("No failed proxies");
          } else {
            console.log(`Failed proxies (${failed.size}):`);
            for (const slug of failed) {
              console.log(`  ${slug}`);
            }
          }
          break;
        }
        case "due": {
          const due = await isAutoTestDue();
          console.log(due ? "Auto-test is due" : "Auto-test is not due");
          break;
        }
        default:
          console.log(`Proxy Health Testing

Usage:
  vpn-proxy tool test single <slug>   Test a single VPN proxy
  vpn-proxy tool test all             Test all VPN proxies
  vpn-proxy tool test results         Show all test results (JSON)
  vpn-proxy tool test failed          List failed proxy slugs
  vpn-proxy tool test due             Check if automated test is due
`);
      }
      break;
    }

    // ======================== Export ========================

    case "export": {
      const format = args[1] || "usernames";
      const onlyWorking = args.includes("--working");
      const vpns = await listVpns();
      const failedSlugs = onlyWorking ? await getFailedSlugs() : new Set();
      const filtered = onlyWorking
        ? vpns.filter((v) => !failedSlugs.has(v.slug))
        : vpns;

      switch (format) {
        case "usernames":
          console.log(filtered.map((v) => v.slug).join(","));
          break;
        case "socks5":
          console.log(
            filtered
              .map((v) => `socks5h://${v.slug}@127.0.0.1:${CONFIG.SOCKS5_PORT}`)
              .join(","),
          );
          break;
        case "http":
          console.log(
            filtered
              .map((v) => `http://${v.slug}:@127.0.0.1:${CONFIG.HTTP_PORT}`)
              .join(","),
          );
          break;
        default:
          console.log(`Export Proxy Lists

Usage:
  vpn-proxy tool export usernames [--working]   Comma-separated slugs
  vpn-proxy tool export socks5 [--working]      Comma-separated SOCKS5 URLs
  vpn-proxy tool export http [--working]        Comma-separated HTTP URLs

Options:
  --working    Only include proxies that passed their last health test
`);
      }
      break;
    }

    // ======================== Pattern ========================

    case "match": {
      const pattern = args.slice(1).join(" ");
      if (!pattern) {
        console.error("Usage: vpn-proxy tool match <pattern>");
        console.error("  e.g., 'GB', 'Manchester', 'Ceibo'");
        process.exit(1);
      }
      const matches = await resolveVpnByPattern(pattern);
      if (matches.length === 0) {
        console.error(`No VPNs match pattern: ${pattern}`);
        process.exit(1);
      }
      console.log(`Matched ${matches.length} VPN(s):`);
      for (const vpn of matches) {
        console.log(`  ${vpn.flag} ${vpn.displayName} (${vpn.slug})`);
      }
      break;
    }

    // ======================== Status (enhanced) ========================

    case "status-json": {
      const state = await loadState();
      const settings = await loadSettings();
      const activeCount = Object.keys(state.namespaces).length;
      console.log(
        JSON.stringify(
          {
            ...state,
            activeCount,
            currentTimeoutSeconds: getDynamicIdleTimeout(
              activeCount,
              settings.idleTimeoutTiers,
            ),
          },
          null,
          2,
        ),
      );
      break;
    }

    case "help":
    default:
      console.log(`VPN Proxy Tools

Usage:
  vpn-proxy tool                       Launch interactive TUI
  vpn-proxy tool list-usernames        List all VPN usernames
  vpn-proxy tool list-socks5           List all SOCKS5 proxy URLs
  vpn-proxy tool list-http             List all HTTP proxy URLs
  vpn-proxy tool random-username       Get a random VPN username
  vpn-proxy tool random-socks5         Get a random SOCKS5 proxy URL
  vpn-proxy tool random-http           Get a random HTTP proxy URL
  vpn-proxy tool health <target>       Health check a username or proxy URL
  vpn-proxy tool match <pattern>       Find VPNs matching a pattern
  vpn-proxy tool status-json           Full proxy state as JSON
  vpn-proxy tool settings ...          Manage persistent settings
  vpn-proxy tool test ...              Proxy health testing
  vpn-proxy tool export ...            Export proxy lists
`);
  }
}

// ============================================================================
// Helpers
// ============================================================================

function setNestedValue(
  obj: Record<string, unknown>,
  path: string,
  value: unknown,
): void {
  const parts = path.split(".");
  let current: Record<string, unknown> = obj;
  for (let i = 0; i < parts.length - 1; i++) {
    const part = parts[i]!;
    if (typeof current[part] !== "object" || current[part] === null) {
      current[part] = {};
    }
    current = current[part] as Record<string, unknown>;
  }
  current[parts[parts.length - 1]!] = value;
}

function parseCliValue(value: string): unknown {
  if (value === "true") return true;
  if (value === "false") return false;
  if (value === "null") return null;
  const num = Number(value);
  if (!isNaN(num) && value.trim() !== "") return num;
  try {
    const parsed = JSON.parse(value);
    if (typeof parsed === "object") return parsed;
  } catch {
    // Not JSON
  }
  return value;
}

// ============================================================================
// Health Check
// ============================================================================

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

// ============================================================================
// Interactive TUI
// ============================================================================

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
  console.log("6. Match pattern");
  console.log("7. Show settings");
  console.log("8. Test all proxies");
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
    case "6": {
      const pattern = await question(
        "\nEnter pattern (e.g., GB, Manchester): ",
      );
      if (pattern) {
        const matches = await resolveVpnByPattern(pattern);
        if (matches.length === 0) {
          console.log(`No VPNs match: ${pattern}`);
        } else {
          console.log(`\nMatched ${matches.length} VPN(s):`);
          for (const vpn of matches) {
            console.log(`  ${vpn.flag} ${vpn.displayName}`);
          }
        }
      }
      break;
    }
    case "7": {
      const settings = await loadSettings();
      console.log("\n" + JSON.stringify(settings, null, 2));
      break;
    }
    case "8": {
      console.log("\nStarting full proxy test...\n");
      await testAllProxies((completed, total, result) => {
        const icon = result.success ? "✓" : "✗";
        console.log(
          `[${completed}/${total}] ${icon} ${result.displayName}${result.success ? ` (${result.latencyMs}ms)` : ` — ${result.error}`}`,
        );
      });
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
