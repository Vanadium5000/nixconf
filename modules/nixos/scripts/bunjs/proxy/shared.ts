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
import { readFile, writeFile, mkdir, unlink } from "fs/promises";
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

/** State directory in tmpfs - fast and auto-cleaned on reboot */
export const STATE_DIR = `/dev/shm/vpn-proxy-${process.getuid!()}`;
export const STATE_FILE = join(STATE_DIR, "state.json");

/** Path to network namespace setup script */
export const NETNS_SCRIPT =
  process.env.VPN_PROXY_NETNS_SCRIPT || join(import.meta.dir, "netns.sh");

// Environment configuration with defaults
export const CONFIG = {
  /** SOCKS5 proxy port */
  SOCKS5_PORT: parseInt(process.env.VPN_PROXY_PORT || "10800", 10),
  /** HTTP CONNECT proxy port */
  HTTP_PORT: parseInt(process.env.VPN_HTTP_PROXY_PORT || "10801", 10),
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
  component = "vpn-proxy"
): void {
  const timestamp = new Date().toISOString();
  console.error(`[${timestamp}] [${level}] [${component}] ${message}`);
}

// ============================================================================
// Desktop Notifications
// ============================================================================

/**
 * Send a desktop notification via notify-send
 * Fails silently if no display is available (e.g., running as service)
 */
export async function notify(
  title: string,
  message: string,
  urgency: "low" | "normal" | "critical" = "normal"
): Promise<void> {
  try {
    await spawn({
      cmd: ["notify-send", "-u", urgency, title, message],
      stdout: "ignore",
      stderr: "ignore",
    }).exited;
  } catch {
    // Notification failed (e.g., no display), log instead
    log("INFO", `[notify] ${title}: ${message}`);
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
 * State is persisted to tmpfs for sharing between processes
 */
export async function saveState(state: ProxyState): Promise<void> {
  await ensureStateDir();
  await writeFile(STATE_FILE, JSON.stringify(state, null, 2));
}

// ============================================================================
// Network Namespace Script Execution
// ============================================================================

/**
 * Execute the network namespace setup script with sudo if needed
 */
export function runNetnsScript(
  args: string[],
  options: { notifySudo?: boolean } = {}
): { success: boolean; output: string } {
  const needsSudo = process.getuid!() !== 0;
  const sudoPrefix = needsSudo ? ["sudo"] : [];

  if (needsSudo && options.notifySudo) {
    notify("VPN Proxy", "Requesting sudo for network namespace setup", "normal");
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
    throw new Error(`OpenVPN failed: ${stderr}`);
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
  timeout = 30000
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
 */
export async function createNamespace(
  state: ProxyState,
  vpn: VpnConfig
): Promise<NamespaceInfo> {
  const nsIndex = state.nextIndex;
  const nsName = `vpn-proxy-${nsIndex}`;
  const nsIp = `10.200.${nsIndex}.2`;

  log("INFO", `Creating namespace ${nsName} for ${vpn.displayName}`);

  const result = runNetnsScript(
    [
      "create",
      nsName,
      nsIndex.toString(),
      vpn.serverIp,
      vpn.serverPort.toString(),
    ],
    { notifySudo: true }
  );

  if (!result.success) {
    log("ERROR", `Failed to create namespace: ${result.output}`);
    throw new Error(`Namespace creation failed`);
  }

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
    socksPort: 10900 + nsIndex, // microsocks port inside namespace
    slug: vpn.slug,
    vpnDisplayName: vpn.displayName,
    lastUsed: Date.now(),
    openvpnPid,
    status: "connected",
  };

  state.namespaces[vpn.slug] = info;
  state.nextIndex++;
  await saveState(state);

  log("INFO", `Namespace ${nsName} ready for ${vpn.displayName}`);
  return info;
}

/**
 * Destroy a namespace and clean up all resources
 */
export async function destroyNamespace(
  slug: string,
  state: ProxyState
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
 */
export async function isNamespaceHealthy(info: NamespaceInfo): Promise<boolean> {
  const sudoPrefix = process.getuid!() === 0 ? [] : ["sudo"];

  // Check namespace exists
  const nsCheck = spawnSync([...sudoPrefix, "ip", "netns", "list"]);
  if (!nsCheck.stdout.toString().includes(info.nsName)) {
    log("WARN", `Namespace ${info.nsName} no longer exists`);
    return false;
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
 */
export async function getOrCreateNamespace(
  slug: string,
  state: ProxyState
): Promise<NamespaceInfo> {
  const existing = state.namespaces[slug];
  if (existing && existing.status === "connected") {
    if (await isNamespaceHealthy(existing)) {
      existing.lastUsed = Date.now();
      await saveState(state);
      return existing;
    }
    log("WARN", `Namespace for ${slug} is stale, recreating`);
    await destroyNamespace(slug, state);
  }

  const vpn = await resolveVpn(slug);
  if (!vpn) throw new Error(`VPN not found: ${slug}`);

  return createNamespace(state, vpn);
}

// ============================================================================
// VPN Slug Resolution
// ============================================================================

/**
 * Resolve username/auth to VPN slug
 *
 * - Empty or "random" → rotating random VPN
 * - Valid VPN name → that specific VPN
 * - Invalid name → notify user, fall back to random
 */
export async function resolveSlugFromUsername(
  username: string,
  state: ProxyState
): Promise<string> {
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
    await notify(
      "VPN Proxy",
      `Invalid VPN name "${username}", using random VPN`,
      "normal"
    );
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
        await notify("VPN Proxy", `Random VPN rotated to ${vpn.displayName}`, "low");
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

  await notify("VPN Proxy", `Random VPN rotated to ${vpn.displayName}`, "normal");

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
      Math.floor((state.random.expiresAt - now) / 1000)
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
