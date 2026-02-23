#!/usr/bin/env bun
/**
 * VPN Proxy Shared Utilities
 *
 * Common functionality shared between SOCKS5 and HTTP proxy servers:
 * - State management (namespaces, random VPN selection)
 * - Logging with consistent format
 * - Network namespace lifecycle management
 * - Desktop notifications
 *
 * State is stored in tmpfs at /dev/shm/vpn-proxy-$UID/ for:
 * - Speed (RAM-backed filesystem)
 * - Automatic cleanup on reboot
 * - No persistence across reboots (namespaces are ephemeral anyway)
 */

import { spawn, spawnSync } from "bun";
import {
  readFile,
  writeFile,
  mkdir,
  unlink,
  rename,
  rm,
  stat as fsStat,
} from "fs/promises";
import { join } from "path";
import {
  resolveVpn,
  getRandomVpn,
  isValidSlug,
  type VpnConfig,
} from "./vpn-resolver";

// ============================================================================
// Constants
// ============================================================================

/**
 * State directory in tmpfs - fast and auto-cleaned on reboot
 *
 * The systemd services run as root (UID 0), so state is always stored in
 * /dev/shm/vpn-proxy-0/. CLI commands run as any user but need to read the
 * service's state, so we use UID 0 for the state directory.
 */
export const STATE_DIR = `/dev/shm/vpn-proxy-0`;
export const STATE_FILE = join(STATE_DIR, "state.json");
export const LOCK_FILE = join(STATE_DIR, "state.lock");

/** Path to network namespace setup script */
export const NETNS_SCRIPT =
  process.env.VPN_PROXY_NETNS_SCRIPT || join(import.meta.dir, "netns.sh");

// Environment configuration with defaults
export const CONFIG = {
  /** SOCKS5 proxy port */
  SOCKS5_PORT: parseInt(process.env.VPN_PROXY_PORT || "10800", 10),
  /** HTTP CONNECT proxy port */
  HTTP_PORT: parseInt(process.env.VPN_HTTP_PROXY_PORT || "10801", 10),
  /** Bind address: 0.0.0.0 (all interfaces for LAN sharing) or 127.0.0.1 (localhost only) */
  BIND_ADDRESS: process.env.VPN_PROXY_BIND_ADDRESS || "0.0.0.0",
  /** Seconds before idle namespace cleanup */
  IDLE_TIMEOUT: parseInt(process.env.VPN_PROXY_IDLE_TIMEOUT || "300", 10),
  /** Seconds between random VPN rotation */
  RANDOM_ROTATION: parseInt(process.env.VPN_PROXY_RANDOM_ROTATION || "300", 10),
  /** Show desktop notification on random rotation */
  NOTIFY_ROTATION: process.env.VPN_PROXY_NOTIFY_ROTATION === "1",
} as const;

// ============================================================================
// Types
// ============================================================================

export interface NamespaceInfo {
  nsName: string;
  nsIndex: number;
  nsIp: string;
  socksPort: number;
  slug: string;
  vpnDisplayName: string;
  lastUsed: number;
  openvpnPid: number;
  status: "starting" | "connected" | "failed";
}

export interface ProxyState {
  namespaces: Record<string, NamespaceInfo>;
  random: { currentSlug: string; expiresAt: number } | null;
  nextIndex: number;
}

// ============================================================================
// Logging
// ============================================================================

type LogLevel = "DEBUG" | "INFO" | "WARN" | "ERROR";

/**
 * Log a message with timestamp and component tag
 * All logs go to stderr to keep stdout clean for data output
 */
export function log(
  level: LogLevel,
  message: string,
  component = "vpn-proxy",
): void {
  const timestamp = new Date().toISOString();
  console.error(`[${timestamp}] [${level}] [${component}] ${message}`);
}

// ============================================================================
// Desktop Notifications
// ============================================================================

/**
 * Send a desktop notification via qs-notify (Quickshell notification center)
 *
 * Uses qs-notify which communicates via Quickshell's IPC socket, allowing
 * notifications from systemd services that lack D-Bus session access.
 * Falls back to notify-send if qs-notify unavailable, then silently continues
 * if both fail (e.g., no graphical session).
 */
export async function notify(
  title: string,
  message: string,
  urgency: "low" | "normal" | "critical" = "normal",
): Promise<void> {
  // Try qs-notify first (works from systemd services via Quickshell IPC)
  try {
    const qsResult = await spawn({
      cmd: ["qs-notify", "-u", urgency, "-a", "VPN Proxy", title, message],
      stdout: "ignore",
      stderr: "ignore",
    }).exited;
    if (qsResult === 0) return;
  } catch {
    // qs-notify not available, try fallback
  }

  // Fallback to notify-send (requires D-Bus session access)
  try {
    await spawn({
      cmd: ["notify-send", "-u", urgency, "-a", "VPN Proxy", title, message],
      stdout: "ignore",
      stderr: "ignore",
    }).exited;
  } catch {
    // Both methods failed, log instead and continue silently
    log("DEBUG", `[notify] ${title}: ${message}`);
  }
}

// ============================================================================
// State Management
// ============================================================================

/**
 * Ensure the state directory exists in tmpfs
 */
export async function ensureStateDir(): Promise<void> {
  await mkdir(STATE_DIR, { recursive: true }).catch(() => {});
}

/**
 * Load proxy state from disk
 * Returns empty state if file doesn't exist or is corrupted
 */
export async function loadState(): Promise<ProxyState> {
  try {
    const content = await readFile(STATE_FILE, "utf-8");
    return JSON.parse(content);
  } catch {
    return { namespaces: {}, random: null, nextIndex: 0 };
  }
}

/**
 * Save proxy state to disk
 * Uses atomic write (write to temp file then rename) to prevent corruption
 * when multiple processes write concurrently.
 */
export async function saveState(state: ProxyState): Promise<void> {
  await ensureStateDir();
  const tmpFile = `${STATE_FILE}.tmp.${process.pid}`;
  await writeFile(tmpFile, JSON.stringify(state, null, 2));
  // rename is atomic on the same filesystem (tmpfs)
  await rename(tmpFile, STATE_FILE);
}

// ============================================================================
// Mutex / Locking
// ============================================================================

/**
 * Cross-process file lock using atomic mkdir
 *
 * Both SOCKS5 and HTTP proxy are separate systemd services sharing state.json.
 * The in-memory mutex only protects within a single process; this lock
 * serializes namespace creation across processes to prevent state corruption
 * and duplicate namespace creation.
 *
 * Uses mkdir as the atomic primitive: mkdir fails if the directory already
 * exists, making it a reliable cross-process lock. Includes a stale lock
 * timeout (60s) to recover from crashed processes.
 */
const LOCK_DIR = `${LOCK_FILE}.d`;
const LOCK_STALE_MS = 60_000; // 60s stale lock timeout

async function withFileLock<T>(fn: () => Promise<T>): Promise<T> {
  await ensureStateDir();
  const deadline = Date.now() + 30_000; // 30s acquisition timeout

  // Spin until we acquire the lock or timeout
  while (true) {
    try {
      await mkdir(LOCK_DIR);
      // Lock acquired — write PID for stale detection
      await writeFile(join(LOCK_DIR, "pid"), `${process.pid}\n`);
      break;
    } catch {
      // Lock exists — check if it's stale (holder crashed)
      try {
        const lockStat = await fsStat(LOCK_DIR);
        if (Date.now() - lockStat.mtimeMs > LOCK_STALE_MS) {
          log("WARN", "Breaking stale file lock (holder likely crashed)");
          await rm(LOCK_DIR, { recursive: true, force: true });
          continue; // Retry immediately
        }
      } catch {
        // Lock dir vanished between our check — retry
        continue;
      }

      if (Date.now() > deadline) {
        log("WARN", "File lock acquisition timed out, proceeding anyway");
        break;
      }
      await Bun.sleep(50);
    }
  }

  try {
    return await fn();
  } finally {
    // Release lock
    try {
      await rm(LOCK_DIR, { recursive: true, force: true });
    } catch {
      // Best-effort cleanup
    }
  }
}

/**
 * In-memory mutex for namespace creation
 *
 * Prevents race conditions when multiple concurrent requests within the same
 * process try to create namespaces simultaneously. Each slug gets its own lock
 * to allow parallel creation of different VPNs while serializing requests for
 * the same VPN.
 */
const namespaceLocks = new Map<string, Promise<void>>();

/**
 * Acquire both in-process and cross-process locks for a slug
 * This ensures only one namespace creation happens per slug across all processes
 */
async function withNamespaceLock<T>(
  slug: string,
  fn: () => Promise<T>,
): Promise<T> {
  // Wait for any existing in-process lock on this slug
  const existingLock = namespaceLocks.get(slug);
  if (existingLock) {
    await existingLock;
  }

  // Create a new in-process lock for our operation
  let releaseLock: () => void;
  const lockPromise = new Promise<void>((resolve) => {
    releaseLock = resolve;
  });
  namespaceLocks.set(slug, lockPromise);

  try {
    // Wrap the actual work in a cross-process file lock
    return await withFileLock(fn);
  } finally {
    releaseLock!();
    // Only delete if this is still our lock (another request might have queued)
    if (namespaceLocks.get(slug) === lockPromise) {
      namespaceLocks.delete(slug);
    }
  }
}

// ============================================================================
// Network Namespace Script Execution
// ============================================================================

/**
 * Execute the network namespace setup script with sudo if needed
 */
export function runNetnsScript(
  args: string[],
  options: { notifySudo?: boolean } = {},
): { success: boolean; output: string } {
  const needsSudo = process.getuid!() !== 0;
  const sudoPrefix = needsSudo ? ["sudo"] : [];

  if (needsSudo && options.notifySudo) {
    notify(
      "VPN Proxy",
      "Requesting sudo for network namespace setup",
      "normal",
    );
  }

  const result = spawnSync([...sudoPrefix, "bash", NETNS_SCRIPT, ...args]);
  const output = result.stdout.toString() + result.stderr.toString();
  return { success: result.exitCode === 0, output };
}

// ============================================================================
// Namespace Lifecycle
// ============================================================================

/**
 * Start OpenVPN daemon inside a network namespace
 * Returns the PID of the daemonized OpenVPN process
 */
async function startOpenVPN(nsName: string, vpn: VpnConfig): Promise<number> {
  log("INFO", `Starting OpenVPN in ${nsName}`);

  const pidFile = join(STATE_DIR, `openvpn-${nsName}.pid`);
  const logFile = join(STATE_DIR, `openvpn-${nsName}.log`);

  const sudoPrefix = process.getuid!() === 0 ? [] : ["sudo"];
  const proc = spawn({
    cmd: [
      ...sudoPrefix,
      "ip",
      "netns",
      "exec",
      nsName,
      "openvpn",
      "--config",
      vpn.ovpnPath,
      "--dev",
      "tun0",
      "--daemon",
      "--writepid",
      pidFile,
      "--log",
      logFile,
    ],
    stdout: "ignore",
    stderr: "pipe",
  });

  await proc.exited;

  if (proc.exitCode !== 0) {
    const stderr = await new Response(proc.stderr).text();
    // --daemon mode writes errors to the log file, not stderr
    // Read the log file for the actual error if stderr is empty
    let errorDetail = stderr.trim();
    if (!errorDetail) {
      try {
        const logContent = await readFile(logFile, "utf-8");
        // Take last few lines which usually contain the error
        const lines = logContent.trim().split("\n");
        errorDetail = lines.slice(-5).join(" | ");
      } catch {
        errorDetail = "(no error output - check log file)";
      }
    }
    throw new Error(`OpenVPN failed: ${errorDetail}`);
  }

  // Wait for daemon to write PID file
  await Bun.sleep(2000);

  try {
    const pid = parseInt(await readFile(pidFile, "utf-8"), 10);
    log("INFO", `OpenVPN started with PID ${pid}`);
    return pid;
  } catch {
    throw new Error("OpenVPN PID file not found");
  }
}

/**
 * Wait for VPN tunnel interface to come up
 * Polls for tun0 device in the namespace with configurable timeout
 */
async function waitForTunnel(
  nsName: string,
  timeout = 30000,
): Promise<boolean> {
  const start = Date.now();
  const sudoPrefix = process.getuid!() === 0 ? [] : ["sudo"];

  while (Date.now() - start < timeout) {
    const result = spawnSync([
      ...sudoPrefix,
      "ip",
      "netns",
      "exec",
      nsName,
      "ip",
      "addr",
      "show",
      "tun0",
    ]);
    if (result.exitCode === 0) {
      log("INFO", `Tunnel tun0 up in ${nsName}`);
      return true;
    }
    await Bun.sleep(500);
  }

  log("ERROR", `Timeout waiting for tunnel in ${nsName}`);
  return false;
}

/**
 * Create a new network namespace with VPN tunnel
 *
 * Steps:
 * 1. Call netns.sh to create isolated namespace with kill-switch
 * 2. Start OpenVPN daemon inside namespace
 * 3. Wait for tun0 interface to come up
 * 4. Update state with new namespace info
 *
 * On failure: always cleans up the partial namespace and advances nextIndex
 * to avoid infinite retry loops on the same broken index.
 */
export async function createNamespace(
  state: ProxyState,
  vpn: VpnConfig,
): Promise<NamespaceInfo> {
  const nsIndex = state.nextIndex;
  const subnet = (nsIndex % 254) + 1;
  const nsName = `vpn-proxy-${nsIndex}`;
  const nsIp = `10.200.${subnet}.2`;

  // Always advance nextIndex so failed indexes are never reused
  state.nextIndex++;
  await saveState(state);

  log("INFO", `Creating namespace ${nsName} for ${vpn.displayName}`);

  const result = runNetnsScript(
    [
      "create",
      nsName,
      nsIndex.toString(),
      vpn.serverIp,
      vpn.serverPort.toString(),
    ],
    { notifySudo: true },
  );

  if (!result.success) {
    log("ERROR", `Failed to create namespace: ${result.output}`);
    // Clean up any partial namespace state
    runNetnsScript(["destroy", nsName]);
    throw new Error(`Namespace creation failed: ${result.output}`);
  }

  try {
    const openvpnPid = await startOpenVPN(nsName, vpn);
    const tunnelUp = await waitForTunnel(nsName);

    if (!tunnelUp) {
      runNetnsScript(["destroy", nsName]);
      throw new Error("VPN tunnel failed to establish");
    }

    const info: NamespaceInfo = {
      nsName,
      nsIndex,
      nsIp,
      socksPort: 10900 + (nsIndex % 50000), // microsocks port inside namespace
      slug: vpn.slug,
      vpnDisplayName: vpn.displayName,
      lastUsed: Date.now(),
      openvpnPid,
      status: "connected",
    };

    state.namespaces[vpn.slug] = info;
    await saveState(state);

    log("INFO", `Namespace ${nsName} ready for ${vpn.displayName}`);
    return info;
  } catch (error) {
    // OpenVPN or tunnel failed - destroy the namespace to avoid stale state
    log("ERROR", `Namespace ${nsName} setup failed, cleaning up: ${error}`);
    runNetnsScript(["destroy", nsName]);
    throw error;
  }
}

/**
 * Create a direct network namespace (no VPN, no kill-switch)
 *
 * Bypasses any device-level VPN by using a separate network namespace with
 * its own routing table. Traffic goes directly through the host's real
 * interface via NAT masquerading — no OpenVPN, no nftables kill-switch.
 *
 * Steps:
 * 1. Call netns.sh create-direct to set up namespace with veth/NAT/DNS/microsocks
 * 2. Update state with new namespace info (no OpenVPN PID)
 */
export async function createDirectNamespace(
  state: ProxyState,
): Promise<NamespaceInfo> {
  const nsIndex = state.nextIndex;
  const nsName = `vpn-proxy-${nsIndex}`;
  const nsIp = `10.200.${nsIndex}.2`;

  log("INFO", `Creating direct namespace ${nsName} (no VPN)`);

  const result = runNetnsScript(["create-direct", nsName, nsIndex.toString()], {
    notifySudo: true,
  });

  if (!result.success) {
    log("ERROR", `Failed to create direct namespace: ${result.output}`);
    throw new Error(`Direct namespace creation failed`);
  }

  const info: NamespaceInfo = {
    nsName,
    nsIndex,
    nsIp,
    socksPort: 10900 + nsIndex, // microsocks port inside namespace
    slug: "none",
    vpnDisplayName: "Direct (no VPN)",
    lastUsed: Date.now(),
    openvpnPid: -1, // Sentinel: no OpenVPN process (avoids process.kill(0,0) footgun)
    status: "connected",
  };

  state.namespaces["none"] = info;
  state.nextIndex++;
  await saveState(state);

  log("INFO", `Direct namespace ${nsName} ready`);
  return info;
}

/**
 * Destroy a namespace and clean up all resources
 */
export async function destroyNamespace(
  slug: string,
  state: ProxyState,
): Promise<void> {
  const info = state.namespaces[slug];
  if (!info) return;

  log("INFO", `Destroying namespace for ${slug}`);
  runNetnsScript(["destroy", info.nsName]);

  delete state.namespaces[slug];
  await saveState(state);
}

/**
 * Check if a namespace is still healthy
 * Verifies: namespace exists, tun0 is up, OpenVPN process is running
 * For "none" (direct) namespaces: only checks namespace + veth interface
 */
export async function isNamespaceHealthy(
  info: NamespaceInfo,
): Promise<boolean> {
  const sudoPrefix = process.getuid!() === 0 ? [] : ["sudo"];

  // Check namespace exists
  const nsCheck = spawnSync([...sudoPrefix, "ip", "netns", "list"]);
  if (!nsCheck.stdout.toString().includes(info.nsName)) {
    log("WARN", `Namespace ${info.nsName} no longer exists`);
    return false;
  }

  // Direct namespaces have no tun0 or OpenVPN — just verify veth is up
  if (info.slug === "none") {
    const vethCheck = spawnSync([
      ...sudoPrefix,
      "ip",
      "netns",
      "exec",
      info.nsName,
      "ip",
      "link",
      "show",
      `veth-n-${info.nsIndex}`,
    ]);
    if (vethCheck.exitCode !== 0) {
      log("WARN", `veth-n-${info.nsIndex} not found in ${info.nsName}`);
      return false;
    }
    return true;
  }

  // Check tunnel interface exists
  const tunCheck = spawnSync([
    ...sudoPrefix,
    "ip",
    "netns",
    "exec",
    info.nsName,
    "ip",
    "link",
    "show",
    "tun0",
  ]);
  if (tunCheck.exitCode !== 0) {
    log("WARN", `Tunnel tun0 not found in ${info.nsName}`);
    return false;
  }

  // Check OpenVPN process is alive
  try {
    process.kill(info.openvpnPid, 0);
  } catch {
    log("WARN", `OpenVPN process ${info.openvpnPid} is dead`);
    return false;
  }

  return true;
}

/**
 * Get existing namespace or create new one for a VPN slug
 * Handles stale namespace detection and recreation
 *
 * Uses a per-slug mutex to prevent race conditions when multiple concurrent
 * requests try to create the same namespace simultaneously.
 */
export async function getOrCreateNamespace(
  slug: string,
  state: ProxyState,
): Promise<NamespaceInfo> {
  return withNamespaceLock(slug, async () => {
    // Re-load state inside the lock to get the latest version
    // (another request may have created the namespace while we were waiting)
    const freshState = await loadState();

    const existing = freshState.namespaces[slug];
    if (existing && existing.status === "connected") {
      if (await isNamespaceHealthy(existing)) {
        existing.lastUsed = Date.now();
        await saveState(freshState);
        // Also update the caller's state reference
        Object.assign(state, freshState);
        return existing;
      }
      log("WARN", `Namespace for ${slug} is stale, recreating`);
      await destroyNamespace(slug, freshState);
    }

    // Direct namespace — no VPN resolution needed
    if (slug === "none") {
      const result = await createDirectNamespace(freshState);
      Object.assign(state, freshState);
      return result;
    }

    const vpn = await resolveVpn(slug);
    if (!vpn) throw new Error(`VPN not found: ${slug}`);

    const result = await createNamespace(freshState, vpn);
    // Update caller's state reference
    Object.assign(state, freshState);
    return result;
  });
}

// ============================================================================
// VPN Slug Resolution
// ============================================================================

/**
 * Resolve username/auth to VPN slug
 *
 * - Empty or "random" → rotating random VPN
 * - "none" → direct connection (no VPN, bypasses device VPN)
 * - Valid VPN name → that specific VPN
 * - Invalid name → notify user, fall back to random
 */
export async function resolveSlugFromUsername(
  username: string,
  state: ProxyState,
): Promise<string> {
  // Direct connection — bypass VPN entirely
  if (username === "none") {
    return "none";
  }

  if (!username || username === "random") {
    const now = Date.now();
    if (state.random && state.random.expiresAt > now) {
      return state.random.currentSlug;
    }

    const vpn = await getRandomVpn();
    if (!vpn) throw new Error("No VPNs available");

    state.random = {
      currentSlug: vpn.slug,
      expiresAt: now + CONFIG.RANDOM_ROTATION * 1000,
    };
    await saveState(state);
    log("INFO", `Random VPN selected: ${vpn.displayName}`);
    return vpn.slug;
  }

  const isValid = await isValidSlug(username);
  if (!isValid) {
    log("WARN", `Invalid slug "${username}", falling back to random`);
    // Fire-and-forget notification - don't await to avoid blocking on failure
    notify(
      "VPN Proxy",
      `Invalid VPN name "${username}", using random VPN`,
      "normal",
    ).catch(() => {}); // Silently ignore notification failures
    return resolveSlugFromUsername("random", state);
  }

  return username;
}

// ============================================================================
// Cleanup Operations
// ============================================================================

/**
 * Clean up namespaces that have been idle beyond the timeout
 * Returns the number of namespaces cleaned
 */
export async function cleanupIdleProxies(): Promise<number> {
  const state = await loadState();
  const now = Date.now();
  const threshold = now - CONFIG.IDLE_TIMEOUT * 1000;
  let cleaned = 0;

  for (const [slug, info] of Object.entries(state.namespaces)) {
    if (info.lastUsed < threshold) {
      log("INFO", `Cleaning idle: ${slug}`);
      await destroyNamespace(slug, state);
      cleaned++;
    }
  }

  return cleaned;
}

/**
 * Rotate the random VPN if its expiration has passed
 * Returns the new VPN display name if rotated, null otherwise
 */
export async function rotateRandom(): Promise<string | null> {
  const state = await loadState();
  if (!state.random) return null;

  const now = Date.now();
  if (state.random.expiresAt <= now) {
    const oldSlug = state.random.currentSlug;
    const vpn = await getRandomVpn();
    if (vpn && vpn.slug !== oldSlug) {
      state.random = {
        currentSlug: vpn.slug,
        expiresAt: now + CONFIG.RANDOM_ROTATION * 1000,
      };
      await saveState(state);
      log("INFO", `Random rotated: ${oldSlug} -> ${vpn.displayName}`);

      if (CONFIG.NOTIFY_ROTATION) {
        await notify(
          "VPN Proxy",
          `Random VPN rotated to ${vpn.displayName}`,
          "low",
        );
      }

      return vpn.displayName;
    }
  }
  return null;
}

/**
 * Force immediate rotation of the random VPN
 */
export async function forceRotateRandom(): Promise<string | null> {
  const state = await loadState();
  const now = Date.now();

  const oldSlug = state.random?.currentSlug;
  const vpn = await getRandomVpn();
  if (!vpn) {
    log("ERROR", "No VPNs available for rotation");
    return null;
  }

  state.random = {
    currentSlug: vpn.slug,
    expiresAt: now + CONFIG.RANDOM_ROTATION * 1000,
  };
  await saveState(state);

  const rotationMsg = oldSlug
    ? `Random rotated: ${oldSlug} -> ${vpn.displayName}`
    : `Random set to: ${vpn.displayName}`;
  log("INFO", rotationMsg);

  await notify(
    "VPN Proxy",
    `Random VPN rotated to ${vpn.displayName}`,
    "normal",
  );

  return vpn.displayName;
}

/**
 * Get human-readable status of all proxies
 */
export async function getStatus(): Promise<string> {
  const state = await loadState();
  const now = Date.now();

  let output = `VPN Proxy Status\n${"=".repeat(50)}\n`;
  output += `SOCKS5: localhost:${CONFIG.SOCKS5_PORT}\n`;
  output += `HTTP:   localhost:${CONFIG.HTTP_PORT}\n\n`;

  const namespaces = Object.values(state.namespaces);
  if (namespaces.length === 0) {
    output += "Active VPNs: (none)\n";
  } else {
    output += "Active VPNs:\n";
    for (const ns of namespaces) {
      const idleSecs = Math.floor((now - ns.lastUsed) / 1000);
      const idleMin = Math.floor(idleSecs / 60);
      const idleSec = idleSecs % 60;
      const isRandom = state.random?.currentSlug === ns.slug ? " (random)" : "";
      output += `  ${ns.vpnDisplayName}  idle: ${idleMin}m ${idleSec}s  status: ${ns.status}${isRandom}\n`;
    }
  }

  if (state.random) {
    const expiresIn = Math.max(
      0,
      Math.floor((state.random.expiresAt - now) / 1000),
    );
    const expMin = Math.floor(expiresIn / 60);
    const expSec = expiresIn % 60;
    output += `\nRandom VPN: ${state.random.currentSlug} (expires in ${expMin}m ${expSec}s)\n`;
  }

  output += `\nState: ${STATE_DIR}/\n`;
  output += `Idle timeout: ${CONFIG.IDLE_TIMEOUT}s\n`;

  return output;
}

/**
 * Stop all proxies and clean up all namespaces
 */
export async function stopAllProxies(): Promise<void> {
  log("INFO", "Stopping all proxies");
  runNetnsScript(["cleanup-all"]);
  await unlink(STATE_FILE).catch(() => {});
}

/**
 * Clean up stale state from previous session
 * Called on server startup to ensure clean slate
 */
export async function cleanupStaleState(): Promise<void> {
  log("INFO", "Cleaning up stale state from previous session");

  runNetnsScript(["cleanup-all"]);

  await unlink(STATE_FILE).catch(() => {});

  const state: ProxyState = { namespaces: {}, random: null, nextIndex: 0 };
  await saveState(state);

  log("INFO", "Stale state cleanup complete");
}
