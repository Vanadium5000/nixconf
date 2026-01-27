#!/usr/bin/env bun

import { cleanupIdleProxies, rotateRandom } from "./vpn-proxy";

const CLEANUP_INTERVAL = parseInt(process.env.VPN_PROXY_CLEANUP_INTERVAL || "60", 10) * 1000;

function log(level: string, message: string): void {
  const timestamp = new Date().toISOString();
  console.error(`[${timestamp}] [${level}] [cleanup-daemon] ${message}`);
}

async function runCleanupCycle(): Promise<void> {
  try {
    const cleaned = await cleanupIdleProxies();
    if (cleaned > 0) {
      log("INFO", `Cleaned ${cleaned} idle proxies`);
    }
    await rotateRandom();
  } catch (error) {
    log("ERROR", `Cleanup failed: ${error}`);
  }
}

async function main(): Promise<void> {
  log("INFO", `Cleanup daemon started (interval: ${CLEANUP_INTERVAL / 1000}s)`);
  
  await runCleanupCycle();
  setInterval(runCleanupCycle, CLEANUP_INTERVAL);
  
  process.on("SIGTERM", () => process.exit(0));
  process.on("SIGINT", () => process.exit(0));
}

if (import.meta.main) {
  main().catch((error) => {
    log("ERROR", `Fatal: ${error}`);
    process.exit(1);
  });
}
