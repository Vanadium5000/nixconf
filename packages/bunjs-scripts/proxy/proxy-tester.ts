#!/usr/bin/env bun
/**
 * VPN Proxy Health Testing System
 *
 * Tests proxy connectivity by attempting HTTP requests through each VPN's
 * SOCKS5 proxy. Results are persisted at /var/lib/vpn-proxy/test-results.json
 * so the random VPN selector can exclude failed proxies.
 *
 * Supports single-proxy tests, mass testing of all proxies, and automated
 * scheduled testing (configurable interval, default 24h).
 */

import { readFile, writeFile, mkdir, rename } from "fs/promises";
import { join } from "path";
import { PERSISTENT_DIR, loadSettings } from "./settings";
import { listVpns, type VpnConfig } from "./vpn-resolver";

// ============================================================================
// Constants
// ============================================================================

const TEST_RESULTS_FILE = join(PERSISTENT_DIR, "test-results.json");

/** Public API that returns your IP — lightweight, no auth required */
const TEST_URL = "https://api.ipify.org?format=json";

/** Per-proxy test timeout (10s is generous for a simple HTTP GET) */
const TEST_TIMEOUT_MS = 10_000;

// ============================================================================
// Types
// ============================================================================

export interface ProxyTestResult {
  slug: string;
  displayName: string;
  success: boolean;
  /** Resolved IP address when connected through this VPN */
  ip?: string;
  /** Round-trip time in milliseconds */
  latencyMs?: number;
  error?: string;
  testedAt: number;
}

export interface TestResultsState {
  results: Record<string, ProxyTestResult>;
  lastFullTestAt: number | null;
  lastFullTestDurationMs: number | null;
  nextFullTestAt: number | null;
}

// ============================================================================
// Logging
// ============================================================================

function log(
  level: "DEBUG" | "INFO" | "WARN" | "ERROR",
  message: string,
): void {
  const timestamp = new Date().toISOString();
  console.error(`[${timestamp}] [${level}] [proxy-tester] ${message}`);
}

// ============================================================================
// Persistence
// ============================================================================

async function ensurePersistentDir(): Promise<void> {
  await mkdir(PERSISTENT_DIR, { recursive: true }).catch(() => {});
}

export async function loadTestResults(): Promise<TestResultsState> {
  try {
    const content = await readFile(TEST_RESULTS_FILE, "utf-8");
    return JSON.parse(content) as TestResultsState;
  } catch {
    return {
      results: {},
      lastFullTestAt: null,
      lastFullTestDurationMs: null,
      nextFullTestAt: null,
    };
  }
}

export async function saveTestResults(state: TestResultsState): Promise<void> {
  await ensurePersistentDir();
  const tmpFile = `${TEST_RESULTS_FILE}.tmp.${process.pid}`;
  await writeFile(tmpFile, JSON.stringify(state, null, 2));
  await rename(tmpFile, TEST_RESULTS_FILE);
}

// ============================================================================
// Proxy Testing
// ============================================================================

/**
 * Test a single VPN's connectivity by making an HTTP request through its
 * SOCKS5 proxy namespace. Uses curl with --proxy since Bun's fetch doesn't
 * support SOCKS5 natively.
 */
export async function testSingleProxy(
  vpn: VpnConfig,
  socksPort = 10800,
): Promise<ProxyTestResult> {
  const start = Date.now();

  try {
    const proc = Bun.spawn({
      cmd: [
        "curl",
        "-s",
        "--max-time",
        (TEST_TIMEOUT_MS / 1000).toString(),
        "--proxy",
        `socks5://${encodeURIComponent(vpn.slug)}@127.0.0.1:${socksPort}`,
        TEST_URL,
      ],
      stdout: "pipe",
      stderr: "pipe",
    });

    const exitCode = await proc.exited;
    const stdout = await new Response(proc.stdout).text();
    const latencyMs = Date.now() - start;

    if (exitCode !== 0) {
      const stderr = await new Response(proc.stderr).text();
      return {
        slug: vpn.slug,
        displayName: vpn.displayName,
        success: false,
        latencyMs,
        error: stderr.trim() || `curl exit code ${exitCode}`,
        testedAt: Date.now(),
      };
    }

    let ip: string | undefined;
    try {
      const parsed = JSON.parse(stdout);
      ip = parsed.ip;
    } catch {
      ip = stdout.trim();
    }

    return {
      slug: vpn.slug,
      displayName: vpn.displayName,
      success: true,
      ip,
      latencyMs,
      testedAt: Date.now(),
    };
  } catch (error) {
    return {
      slug: vpn.slug,
      displayName: vpn.displayName,
      success: false,
      latencyMs: Date.now() - start,
      error: String(error),
      testedAt: Date.now(),
    };
  }
}

/**
 * Test all available VPNs sequentially.
 * Sequential to avoid overwhelming the system with simultaneous VPN connections.
 * Emits progress via the optional callback.
 */
export async function testAllProxies(
  onProgress?: (
    completed: number,
    total: number,
    result: ProxyTestResult,
  ) => void,
  signal?: AbortSignal,
): Promise<TestResultsState> {
  const vpns = await listVpns();
  const state = await loadTestResults();
  const startTime = Date.now();
  const settings = await loadSettings();

  // Record start time immediately so the auto-test interval counts from start,
  // not from completion.
  state.lastFullTestAt = startTime;
  state.nextFullTestAt =
    startTime + settings.testing.intervalHours * 60 * 60 * 1000;
  await saveTestResults(state);

  const gapMs = (settings.testing.testGapSeconds ?? 30) * 1000;

  log("INFO", `Starting full proxy test: ${vpns.length} VPNs`);

  for (let i = 0; i < vpns.length; i++) {
    if (signal?.aborted) {
      log("INFO", `Test cancelled at ${i}/${vpns.length}`);
      break;
    }

    const vpn = vpns[i]!;
    log("INFO", `Testing ${i + 1}/${vpns.length}: ${vpn.displayName}`);

    const result = await testSingleProxy(vpn);
    state.results[vpn.slug] = result;

    const status = result.success
      ? `OK (${result.latencyMs}ms, IP: ${result.ip})`
      : `FAIL: ${result.error}`;
    log("INFO", `  ${vpn.displayName}: ${status}`);

    onProgress?.(i + 1, vpns.length, result);

    // Save incrementally so partial results survive crashes
    await saveTestResults(state);

    // Wait between tests to avoid overwhelming VPN connections
    if (i < vpns.length - 1 && gapMs > 0 && !signal?.aborted) {
      try {
        await Promise.race([
          Bun.sleep(gapMs),
          new Promise<never>((_, reject) => {
            if (signal?.aborted) reject(new Error("Aborted"));
            signal?.addEventListener(
              "abort",
              () => reject(new Error("Aborted")),
              { once: true },
            );
          }),
        ]);
      } catch {
        if (signal?.aborted) {
          log("INFO", `Test cancelled during gap at ${i + 1}/${vpns.length}`);
          break;
        }
      }
    }
  }

  state.lastFullTestDurationMs = Date.now() - startTime;
  state.nextFullTestAt =
    Date.now() + settings.testing.intervalHours * 60 * 60 * 1000;
  await saveTestResults(state);

  const passed = Object.values(state.results).filter((r) => r.success).length;
  const failed = Object.values(state.results).filter((r) => !r.success).length;
  log(
    "INFO",
    `Full test complete: ${passed} passed, ${failed} failed (${state.lastFullTestDurationMs}ms)`,
  );

  return state;
}

// ============================================================================
// Query Helpers
// ============================================================================

/**
 * Get slugs of VPNs that failed their last test.
 * Used by random VPN selection to exclude broken proxies.
 */
export async function getFailedSlugs(): Promise<Set<string>> {
  const state = await loadTestResults();
  const settings = await loadSettings();

  if (!settings.testing.excludeFailedFromRandom) {
    return new Set();
  }

  const failed = new Set<string>();
  for (const [slug, result] of Object.entries(state.results)) {
    if (!result.success) {
      failed.add(slug);
    }
  }
  return failed;
}

/**
 * Get test result for a specific VPN slug.
 */
export async function getTestResult(
  slug: string,
): Promise<ProxyTestResult | null> {
  const state = await loadTestResults();
  return state.results[slug] ?? null;
}

/**
 * Check if automated testing is due based on configured interval.
 */
export async function isAutoTestDue(): Promise<boolean> {
  const settings = await loadSettings();
  if (!settings.testing.enabled) return false;

  const state = await loadTestResults();
  if (!state.lastFullTestAt) return true;

  const intervalMs = settings.testing.intervalHours * 60 * 60 * 1000;
  return Date.now() - state.lastFullTestAt >= intervalMs;
}

// ============================================================================
// CLI Interface
// ============================================================================

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  const command = args[0];

  switch (command) {
    case "test": {
      const slug = args[1];
      if (!slug) {
        console.error("Usage: proxy-tester test <slug>");
        process.exit(1);
      }
      const vpns = await listVpns();
      const vpn = vpns.find((v) => v.slug === slug);
      if (!vpn) {
        console.error(`VPN not found: ${slug}`);
        process.exit(1);
      }
      const result = await testSingleProxy(vpn);
      const state = await loadTestResults();
      state.results[vpn.slug] = result;
      await saveTestResults(state);
      console.log(JSON.stringify(result, null, 2));
      break;
    }

    case "test-all": {
      const state = await testAllProxies((completed, total, result) => {
        const icon = result.success ? "✓" : "✗";
        console.log(
          `[${completed}/${total}] ${icon} ${result.displayName}${result.success ? ` (${result.latencyMs}ms)` : ` — ${result.error}`}`,
        );
      });
      const passed = Object.values(state.results).filter(
        (r) => r.success,
      ).length;
      const failed = Object.values(state.results).filter(
        (r) => !r.success,
      ).length;
      console.log(`\nResults: ${passed} passed, ${failed} failed`);
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
      process.exit(due ? 0 : 1);
    }

    default:
      console.log(`VPN Proxy Health Tester

Usage:
  proxy-tester test <slug>    Test a single VPN proxy
  proxy-tester test-all       Test all VPN proxies
  proxy-tester results        Show all test results (JSON)
  proxy-tester failed         List failed proxy slugs
  proxy-tester due            Check if automated test is due (exit 0=due, 1=not due)
`);
  }
}

if (import.meta.main) {
  main().catch((error) => {
    log("ERROR", `Fatal: ${error}`);
    process.exit(1);
  });
}
