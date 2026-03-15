#!/usr/bin/env bun
import { chromium, type Page } from "playwright";

const DEFAULT_URL = "https://duckduckgo.com";

const STEALTH_USER_AGENTS = [
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36",
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36",
  "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Mobile Safari/537.36",
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36",
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36",
] as const;

function getStealthUserAgent(): { ua: string; desc: string } {
  const index =
    Math.floor(Date.now() / (1000 * 60 * 60)) % STEALTH_USER_AGENTS.length;
  const ua = STEALTH_USER_AGENTS[index]!;

  let desc = "Unknown";
  if (ua.includes("Windows")) desc = "Chrome / Windows";
  else if (ua.includes("Macintosh")) desc = "Chrome / macOS";
  else if (ua.includes("Android")) desc = "Chrome / Android";

  return { ua, desc };
}

function parseProxy(
  proxyUrl: string,
): { server: string; username?: string; password?: string } | undefined {
  if (!proxyUrl) return undefined;
  const url = proxyUrl.includes("://") ? proxyUrl : `http://${proxyUrl}`;

  try {
    const parsed = new URL(url);
    const protocol = parsed.protocol.replace(":", "");
    const server = `${protocol}://${parsed.hostname}:${parsed.port || (protocol === "https" ? 443 : 80)}`;

    return {
      server,
      username: parsed.username
        ? decodeURIComponent(parsed.username)
        : undefined,
      password: parsed.password
        ? decodeURIComponent(parsed.password)
        : undefined,
    };
  } catch (error) {
    console.error(`Error parsing proxy URL "${proxyUrl}":`, error);
    return undefined;
  }
}

/**
 * Navigates to a URL with retries for transient network errors.
 * Specifically handles ERR_NETWORK_CHANGED which often occurs during proxy initialization.
 */
async function gotoWithRetry(
  page: Page,
  url: string,
  options: { timeout?: number; maxRetries?: number } = {},
): Promise<void> {
  const { timeout = 60000, maxRetries = 5 } = options;
  let attempt = 0;

  while (attempt < maxRetries) {
    try {
      // Use domcontentloaded to handle slow proxies that might take a while to finish loading all assets
      await page.goto(url, { timeout, waitUntil: "domcontentloaded" });
      return;
    } catch (error: any) {
      attempt++;
      const errorMessage = error.message || "";
      const isNetworkChanged = errorMessage.includes(
        "net::ERR_NETWORK_CHANGED",
      );
      const isTimeout = errorMessage.includes("Timeout");

      if (isNetworkChanged || isTimeout) {
        console.warn(
          `\n⚠️ Navigation attempt ${attempt} failed: ${errorMessage.split("\n")[0]}`,
        );
        if (attempt < maxRetries) {
          const delay = Math.min(1000 * Math.pow(2, attempt), 10000);
          console.log(`   Retrying in ${delay / 1000}s...`);
          await new Promise((resolve) => setTimeout(resolve, delay));
          continue;
        }
      }
      throw error;
    }
  }
}

async function main(): Promise<void> {
  const proxyArg = Bun.argv[2];

  console.log("🎭 Playwright Stealth Browser Launcher");
  console.log("========================================\n");

  const { ua: userAgent, desc: uaDesc } = getStealthUserAgent();
  let proxy = proxyArg ? parseProxy(proxyArg) : undefined;
  const proxyMode = process.env.PLAYWRIGHT_PROXY_MODE || "http";

  if (proxy && proxyMode === "http") {
    if (proxy.server.startsWith("socks5")) {
      proxy = {
        server: `http://127.0.0.1:${process.env.VPN_HTTP_PROXY_PORT || "10801"}`,
      };
    }
  }

  console.log(`User Agent: ${userAgent} (${uaDesc})`);
  console.log(`Proxy:      ${proxy?.server ?? "(none)"}`);
  if (proxyMode !== "http") {
    console.log(`Proxy mode: ${proxyMode}`);
  }

  console.log("\nLaunching Chromium...");

  const browser = await chromium.launch({
    headless: false,
    executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH,
    proxy,
    args: [
      "--disable-blink-features=AutomationControlled",
      "--disable-features=IsolateOrigins,site-per-process",
      "--disable-dev-shm-usage",
      "--no-sandbox",
      "--window-size=1920,1080",
      "--start-maximized",
    ],
  });

  // Bun-specific reliability: Use a promise to track browser closure
  // as process.exit() inside an event listener can sometimes be unreliable
  // if the event loop is heavily loaded or idle.
  let resolveBrowserClosed: () => void;
  const browserClosed = new Promise<void>((resolve) => {
    resolveBrowserClosed = resolve;
  });

  browser.on("disconnected", () => {
    console.log("\n👋 Browser closed, exiting...");
    resolveBrowserClosed();
  });

  // Watchdog interval to ensure we exit even if 'disconnected' event is lost
  // (Common issue in Bun/Playwright integration as of 2026)
  const watchdog = setInterval(() => {
    if (!browser.isConnected()) {
      resolveBrowserClosed();
    }
  }, 1000);

  const context = await browser.newContext({
    userAgent,
    viewport: null,
    locale: "en-US",
    timezoneId: "America/New_York",
  });

  // Set long timeouts to account for slow proxy connections
  // Source: https://playwright.dev/docs/api/class-browsercontext#browser-context-set-default-timeout
  context.setDefaultTimeout(60000); // 60s
  context.setDefaultNavigationTimeout(60000); // 60s

  await context.addInitScript(`
    Object.defineProperty(navigator, "webdriver", {
      get: () => undefined,
      configurable: true,
    });
    if (window.chrome) {
      window.chrome.runtime = window.chrome.runtime || {};
    }
    delete window.__playwright;
    delete window.__pw_scripts;
  `);

  const page = await context.newPage();

  page.on("close", () => {
    console.log("\n👋 Page closed, shutting down browser...");
    browser.close().catch(() => {});
  });

  console.log("\n✅ Browser launched successfully!");
  console.log("\n   Closing the browser window will exit the script.\n");

  try {
    await gotoWithRetry(page, DEFAULT_URL, { timeout: 60000 });
  } catch (error) {
    console.error("\n❌ Initial navigation failed after retries:", error);
    await browser.close().catch(() => {});
    process.exit(1);
  }

  // Wait for the browser to be disconnected before finishing main()
  await browserClosed;
  clearInterval(watchdog);
  process.exit(0);
}

process.on("SIGINT", () => {
  console.log("\n\n👋 Shutting down...");
  process.exit(0);
});

main().catch((error) => {
  console.error("\n❌ Error launching browser:", error);
  process.exit(1);
});
