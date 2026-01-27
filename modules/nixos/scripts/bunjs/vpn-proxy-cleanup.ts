#!/usr/bin/env bun
/**
 * VPN Proxy Cleanup Daemon
 * Periodically cleans up idle proxies and rotates random VPN selection
 */

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
      log("INFO", `Cleaned up ${cleaned} idle proxies`);
    }
    
    await rotateRandom();
  } catch (error) {
    log("ERROR", `Cleanup cycle failed: ${error}`);
  }
}

async function main(): Promise<void> {
  log("INFO", `Starting cleanup daemon (interval: ${CLEANUP_INTERVAL / 1000}s)`);
  
  await runCleanupCycle();
  
  setInterval(runCleanupCycle, CLEANUP_INTERVAL);
  
  process.on("SIGTERM", () => {
    log("INFO", "Received SIGTERM, shutting down");
    process.exit(0);
  });
  
  process.on("SIGINT", () => {
    log("INFO", "Received SIGINT, shutting down");
    process.exit(0);
  });
}

if (import.meta.main) {
  main().catch((error) => {
    log("ERROR", `Fatal error: ${error}`);
    process.exit(1);
  });
}
