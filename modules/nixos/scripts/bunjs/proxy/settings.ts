#!/usr/bin/env bun
/**
 * VPN Proxy Settings Manager
 *
 * Manages persistent proxy configuration stored at /var/lib/vpn-proxy/settings.json.
 * Settings survive reboots (via NixOS impermanence) unlike the ephemeral runtime
 * state in /dev/shm/. Provides configurable:
 *
 * - Dynamic idle timeout tiers (scales with active proxy count to conserve resources)
 * - Pattern-based VPN matching (use country/city/server as proxy username)
 * - Automated proxy health testing schedule
 * - Web UI configuration
 *
 * All settings have sensible defaults and can be partially updated via mergeSettings().
 */

import { readFile, writeFile, mkdir, rename } from "fs/promises";
import { join } from "path";

// ============================================================================
// Constants
// ============================================================================

/**
 * Persistent storage directory — survives reboots via NixOS impermanence.
 * Separate from ephemeral runtime state in /dev/shm/ because settings
 * and test results should persist across restarts.
 */
export const PERSISTENT_DIR =
  process.env.VPN_PROXY_PERSISTENT_DIR || "/var/lib/vpn-proxy";
export const SETTINGS_FILE = join(PERSISTENT_DIR, "settings.json");

// ============================================================================
// Types
// ============================================================================

/**
 * Threshold tier for dynamic idle timeout.
 * When the number of active proxies meets or exceeds `minActive`,
 * the idle timeout is reduced to `timeoutSeconds`.
 * Tiers are evaluated from highest minActive to lowest (most specific first).
 */
export interface IdleTimeoutTier {
  minActive: number;
  timeoutSeconds: number;
}

/**
 * A field extraction pattern for parsing VPN display names into
 * searchable metadata (country, city, server name, etc.).
 */
export interface FieldPattern {
  /** Human-readable name: "country", "city", "server", etc. */
  name: string;
  /**
   * Regex applied to the VPN display name to extract this field.
   * Must contain at least one capture group.
   */
  regex: string;
  /** Which capture group to use (1-indexed). Default: 1 */
  position: number;
}

export interface PatternParsingSettings {
  /** Whether pattern-based proxy matching is active */
  enabled: boolean;
  /**
   * Field extraction rules applied to VPN display names.
   * Each rule extracts a named field (e.g., country, city) from the name.
   */
  fieldPatterns: FieldPattern[];
  /**
   * Regex patterns for tokens to EXCLUDE from pattern matching.
   * Prevents matching against provider names, protocols, port numbers,
   * and other non-unique fields that would match too many VPNs.
   */
  excludePatterns: string[];
}

export interface TestingSettings {
  /** Run automated connectivity tests on a schedule */
  enabled: boolean;
  /** Hours between automated full test runs */
  intervalHours: number;
  /** Filter out VPNs that failed their last test from random selection */
  excludeFailedFromRandom: boolean;
  /** Timestamp of last completed full test (null if never run) */
  lastFullTestAt: number | null;
}

export interface WebUiSettings {
  /** Port for the web management UI and API server */
  port: number;
}

export interface ProxySettings {
  /**
   * Dynamic idle timeout tiers — evaluated from highest minActive downward.
   * When active proxy count >= tier.minActive, that tier's timeout applies.
   * This prevents resource exhaustion when many proxies are active.
   */
  idleTimeoutTiers: IdleTimeoutTier[];

  /** Pattern-based VPN matching configuration */
  patternParsing: PatternParsingSettings;

  /** Automated proxy health testing configuration */
  testing: TestingSettings;

  /** Web UI configuration */
  webUi: WebUiSettings;
}

// ============================================================================
// Defaults
// ============================================================================

/**
 * Default field patterns for AirVPN naming convention:
 * "AirVPN GB Manchester Ceibo UDP 443 Entry3"
 *  ^provider ^CC ^city     ^server ^proto ^port ^entry
 *
 * These extract country code, city name, and server name as matchable fields.
 * Users can customise these in settings for different VPN providers.
 */
const DEFAULT_FIELD_PATTERNS: FieldPattern[] = [
  {
    name: "country",
    // Matches a standalone 2-letter uppercase code surrounded by word boundaries
    regex: "\\b([A-Z]{2})\\b",
    position: 1,
  },
  {
    name: "city",
    // Matches the word after a 2-letter country code (e.g., "GB Manchester" → "Manchester")
    regex: "\\b[A-Z]{2}\\s+([A-Z][a-z]+(?:\\s+[A-Z][a-z]+)*)\\b",
    position: 1,
  },
  {
    name: "server",
    // Matches the capitalized word after city (server name like "Ceibo", "Alderamin")
    regex: "\\b[A-Z]{2}\\s+[A-Z][a-z]+(?:\\s+[A-Z][a-z]+)*\\s+([A-Z][a-z]+)\\b",
    position: 1,
  },
];

/**
 * Tokens to exclude from pattern matching to prevent overly broad matches.
 * These are common in VPN names but not useful as selectors.
 */
const DEFAULT_EXCLUDE_PATTERNS: string[] = [
  "AirVPN", // Provider name — matches ALL proxies
  "\\d+", // Port numbers, entry numbers
  "UDP", // Protocol identifiers
  "TCP",
  "Entry\\d+", // Entry point identifiers
  "SSL",
  "SSH",
  "Wireguard",
];

export function getDefaultSettings(): ProxySettings {
  return {
    idleTimeoutTiers: [
      // Default: 5 minutes (standard single-proxy usage)
      { minActive: 0, timeoutSeconds: 300 },
      // >3 active: reduce to 3 minutes to free resources faster
      { minActive: 3, timeoutSeconds: 180 },
      // >4 active: 2 minutes — moderate pressure
      { minActive: 4, timeoutSeconds: 120 },
      // >6 active: 1 minute — high pressure
      { minActive: 6, timeoutSeconds: 60 },
      // >8 active: 30 seconds — near capacity
      { minActive: 8, timeoutSeconds: 30 },
      // 9-10 active: 20 seconds — aggressive cleanup
      { minActive: 9, timeoutSeconds: 20 },
    ],
    patternParsing: {
      enabled: true,
      fieldPatterns: DEFAULT_FIELD_PATTERNS,
      excludePatterns: DEFAULT_EXCLUDE_PATTERNS,
    },
    testing: {
      enabled: true,
      intervalHours: 24,
      excludeFailedFromRandom: true,
      lastFullTestAt: null,
    },
    webUi: {
      port: parseInt(process.env.VPN_PROXY_WEB_PORT || "10802", 10),
    },
  };
}

// ============================================================================
// Logging
// ============================================================================

function log(
  level: "DEBUG" | "INFO" | "WARN" | "ERROR",
  message: string,
): void {
  const timestamp = new Date().toISOString();
  console.error(`[${timestamp}] [${level}] [settings] ${message}`);
}

// ============================================================================
// Deep Merge Utility
// ============================================================================

/**
 * Deep merge source into target, preserving target structure.
 * Arrays are replaced entirely (not concatenated) since settings arrays
 * like idleTimeoutTiers should be treated as atomic values.
 */
function deepMerge<T>(target: T, source: Partial<T>): T {
  if (target === null || typeof target !== "object" || Array.isArray(target)) {
    return (source ?? target) as T;
  }

  const result = { ...target } as Record<string, unknown>;
  const src = source as Record<string, unknown>;

  for (const key of Object.keys(src)) {
    const sourceVal = src[key];
    const targetVal = result[key];

    if (sourceVal === undefined) continue;

    if (
      sourceVal !== null &&
      typeof sourceVal === "object" &&
      !Array.isArray(sourceVal) &&
      targetVal !== null &&
      typeof targetVal === "object" &&
      !Array.isArray(targetVal)
    ) {
      result[key] = deepMerge(targetVal, sourceVal);
    } else {
      result[key] = sourceVal;
    }
  }

  return result as T;
}

// ============================================================================
// Persistence
// ============================================================================

async function ensurePersistentDir(): Promise<void> {
  await mkdir(PERSISTENT_DIR, { recursive: true }).catch(() => {});
}

/**
 * Load settings from disk, falling back to defaults for any missing fields.
 * Uses deep merge so partial settings files (e.g., from older versions)
 * are filled in with current defaults.
 */
export async function loadSettings(): Promise<ProxySettings> {
  try {
    const content = await readFile(SETTINGS_FILE, "utf-8");
    const stored = JSON.parse(content) as Partial<ProxySettings>;
    return deepMerge(getDefaultSettings(), stored);
  } catch {
    return getDefaultSettings();
  }
}

/**
 * Save settings to disk atomically (write-to-tmp + rename).
 * Same pattern as state.json to prevent corruption from concurrent writes.
 */
export async function saveSettings(settings: ProxySettings): Promise<void> {
  await ensurePersistentDir();
  const tmpFile = `${SETTINGS_FILE}.tmp.${process.pid}`;
  await writeFile(tmpFile, JSON.stringify(settings, null, 2));
  await rename(tmpFile, SETTINGS_FILE);
  log("INFO", "Settings saved");
}

/**
 * Deep merge a partial settings update into the current settings and save.
 * Returns the merged result. Unknown keys are ignored for safety.
 */
export async function mergeSettings(
  partial: Partial<ProxySettings>,
): Promise<ProxySettings> {
  const current = await loadSettings();
  const merged = deepMerge(current, partial);
  await saveSettings(merged);
  return merged;
}

// ============================================================================
// Dynamic Idle Timeout
// ============================================================================

/**
 * Get the appropriate idle timeout for the current number of active proxies.
 * Evaluates tiers from highest minActive downward to find the most specific match.
 *
 * @param activeCount Number of currently active proxy namespaces
 * @param tiers Optional custom tiers (defaults to loaded settings)
 * @returns Timeout in seconds
 */
export function getDynamicIdleTimeout(
  activeCount: number,
  tiers?: IdleTimeoutTier[],
): number {
  const sortedTiers = (tiers ?? getDefaultSettings().idleTimeoutTiers)
    .slice()
    .sort((a, b) => b.minActive - a.minActive);

  for (const tier of sortedTiers) {
    if (activeCount >= tier.minActive) {
      return tier.timeoutSeconds;
    }
  }

  // Fallback if tiers array is empty or has no minActive: 0 entry
  return 300;
}

// ============================================================================
// CLI Interface
// ============================================================================

/**
 * Set a value at a dot-notation path in a nested object.
 * e.g., setNestedValue(obj, "testing.intervalHours", 12)
 */
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

/**
 * Parse a CLI value string into the appropriate JS type.
 * Handles booleans, numbers, and JSON arrays/objects.
 */
function parseValue(value: string): unknown {
  if (value === "true") return true;
  if (value === "false") return false;
  if (value === "null") return null;

  const num = Number(value);
  if (!isNaN(num) && value.trim() !== "") return num;

  try {
    const parsed = JSON.parse(value);
    if (typeof parsed === "object") return parsed;
  } catch {
    // Not JSON — treat as string
  }

  return value;
}

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  const command = args[0];

  switch (command) {
    case "show": {
      const settings = await loadSettings();
      console.log(JSON.stringify(settings, null, 2));
      break;
    }

    case "set": {
      const key = args[1];
      const value = args[2];
      if (!key || value === undefined) {
        console.error("Usage: vpn-proxy settings set <key> <value>");
        console.error("Keys use dot notation: testing.intervalHours 12");
        process.exit(1);
      }

      const settings = await loadSettings();
      setNestedValue(
        settings as unknown as Record<string, unknown>,
        key,
        parseValue(value),
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
      const activeCount = parseInt(args[1] || "0", 10);
      const settings = await loadSettings();
      const timeout = getDynamicIdleTimeout(
        activeCount,
        settings.idleTimeoutTiers,
      );
      console.log(
        `Active: ${activeCount} → Idle timeout: ${timeout}s (${Math.floor(timeout / 60)}m ${timeout % 60}s)`,
      );
      break;
    }

    default:
      console.log(`VPN Proxy Settings Manager

Usage:
  settings show                    Show current settings
  settings set <key> <value>       Update a setting (dot notation)
  settings reset                   Reset to defaults
  settings timeout <active_count>  Show idle timeout for N active proxies

Examples:
  settings set testing.intervalHours 12
  settings set testing.enabled false
  settings set patternParsing.enabled true
  settings timeout 5
`);
  }
}

if (import.meta.main) {
  main().catch((error) => {
    log("ERROR", `Fatal: ${error}`);
    process.exit(1);
  });
}
