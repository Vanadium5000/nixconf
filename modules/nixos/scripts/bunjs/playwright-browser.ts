#!/usr/bin/env bun
import { chromium } from "playwright";

const DEFAULT_URL = "https://duckduckgo.com";

const STEALTH_USER_AGENTS = [
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36",
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36",
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:134.0) Gecko/20100101 Firefox/134.0",
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.2 Safari/605.1.15",
  "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36",
] as const;

function getStealthUserAgent(): string {
  const index =
    Math.floor(Date.now() / (1000 * 60 * 60)) % STEALTH_USER_AGENTS.length;
  return STEALTH_USER_AGENTS[index]!;
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

async function main(): Promise<void> {
  const proxyArg = Bun.argv[2];

  console.log("🎭 Playwright Stealth Browser Launcher");
  console.log("========================================\n");

  const userAgent = getStealthUserAgent();
  const proxy = proxyArg ? parseProxy(proxyArg) : undefined;

  console.log(`User Agent: ${userAgent}`);
  console.log(`Proxy:      ${proxy?.server ?? "(none)"}`);

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

  const context = await browser.newContext({
    userAgent,
    viewport: null,
    locale: "en-US",
    timezoneId: "America/New_York",
  });

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

  console.log("\n✅ Browser launched successfully!");
  console.log("\n   Closing the browser window will exit the script.\n");

  browser.on("disconnected", () => {
    console.log("\n👋 Browser closed, exiting...");
    process.exit(0);
  });

  await page.goto(DEFAULT_URL);

  await new Promise(() => {});
}

process.on("SIGINT", () => {
  console.log("\n\n👋 Shutting down...");
  process.exit(0);
});

main().catch((error) => {
  console.error("\n❌ Error launching browser:", error);
  process.exit(1);
});
