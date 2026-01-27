#!/usr/bin/env bun
/**
 * VPN Resolver Library
 * Provides VPN configuration parsing, caching, and slug resolution for the SOCKS5 proxy system.
 */

import { readdir, stat, readFile, mkdir, writeFile } from "fs/promises";
import { join, basename } from "path";
import { homedir } from "os";

// ============================================================================
// Types
// ============================================================================

export interface VpnConfig {
  slug: string;
  displayName: string;
  countryCode: string;
  flag: string;
  ovpnPath: string;
  serverIp: string;
  serverPort: number;
}

interface CacheData {
  vpns: VpnConfig[];
  dirMtime: number;
  filesMtime: Record<string, number>;
  createdAt: number;
}

// ============================================================================
// Constants
// ============================================================================

const VPN_DIR = process.env.VPN_DIR || join(homedir(), "Shared/VPNs");
const STATE_DIR = `/dev/shm/vpn-proxy-${process.getuid()}`;
const CACHE_FILE = join(STATE_DIR, "resolver-cache.json");

// Country code to flag emoji mapping (ISO 3166-1 alpha-2)
const FLAGS: Record<string, string> = {
  us: "🇺🇸",
  gb: "🇬🇧",
  uk: "🇬🇧",
  de: "🇩🇪",
  fr: "🇫🇷",
  nl: "🇳🇱",
  ca: "🇨🇦",
  au: "🇦🇺",
  jp: "🇯🇵",
  sg: "🇸🇬",
  ch: "🇨🇭",
  se: "🇸🇪",
  no: "🇳🇴",
  fi: "🇫🇮",
  it: "🇮🇹",
  es: "🇪🇸",
  br: "🇧🇷",
  mx: "🇲🇽",
  in: "🇮🇳",
  kr: "🇰🇷",
  hk: "🇭🇰",
  ie: "🇮🇪",
  at: "🇦🇹",
  be: "🇧🇪",
  dk: "🇩🇰",
  pl: "🇵🇱",
  cz: "🇨🇿",
  ro: "🇷🇴",
  za: "🇿🇦",
  nz: "🇳🇿",
  ar: "🇦🇷",
  cl: "🇨🇱",
  co: "🇨🇴",
  pt: "🇵🇹",
  ru: "🇷🇺",
  bg: "🇧🇬",
  hr: "🇭🇷",
  cy: "🇨🇾",
  ee: "🇪🇪",
  gr: "🇬🇷",
  hu: "🇭🇺",
  is: "🇮🇸",
  lv: "🇱🇻",
  lt: "🇱🇹",
  lu: "🇱🇺",
  mt: "🇲🇹",
  md: "🇲🇩",
  me: "🇲🇪",
  mk: "🇲🇰",
  rs: "🇷🇸",
  sk: "🇸🇰",
  si: "🇸🇮",
  ua: "🇺🇦",
  tr: "🇹🇷",
  il: "🇮🇱",
  ae: "🇦🇪",
  th: "🇹🇭",
  vn: "🇻🇳",
  my: "🇲🇾",
  ph: "🇵🇭",
  id: "🇮🇩",
  tw: "🇹🇼",
  cn: "🇨🇳",
};

// Known country codes for word-boundary matching
const KNOWN_CODES = [
  "GB",
  "UK",
  "US",
  "CA",
  "AU",
  "NZ",
  "DE",
  "FR",
  "NL",
  "BE",
  "AT",
  "CH",
  "SE",
  "NO",
  "FI",
  "DK",
  "IE",
  "IT",
  "ES",
  "PT",
  "PL",
  "CZ",
  "RO",
  "BG",
  "HR",
  "HU",
  "GR",
  "SI",
  "SK",
  "LT",
  "LV",
  "EE",
  "LU",
  "MT",
  "IS",
  "UA",
  "RS",
  "ME",
  "MK",
  "MD",
  "CY",
  "TR",
  "RU",
  "JP",
  "KR",
  "SG",
  "HK",
  "TW",
  "CN",
  "TH",
  "VN",
  "MY",
  "PH",
  "ID",
  "IN",
  "IL",
  "AE",
  "BR",
  "MX",
  "AR",
  "CL",
  "CO",
  "ZA",
];

// ============================================================================
// Logging
// ============================================================================

function log(
  level: "DEBUG" | "INFO" | "WARN" | "ERROR",
  message: string
): void {
  const timestamp = new Date().toISOString();
  console.error(`[${timestamp}] [${level}] [vpn-resolver] ${message}`);
}

// ============================================================================
// Country Code Extraction (ported from qs-vpn bash logic)
// ============================================================================

/**
 * Extract country code from filename.
 * Handles formats like:
 * - "AirVPN AT Vienna Alderamin" -> "AT"
 * - "AirVPN_GB_London" -> "GB"
 * - "us-server" -> "US"
 */
function getCountryCode(filename: string): string {
  const baseName = basename(filename, ".ovpn");

  // Pattern 1: Standalone 2-letter code surrounded by separators
  // e.g., "AirVPN_AT_Vienna" or "AirVPN AT Vienna" -> "AT"
  const pattern1 = /[_\s]([A-Z]{2})[_\s]/;
  const match1 = baseName.match(pattern1);
  if (match1) return match1[1];

  // Pattern 2: "Provider CC City" format (code followed by space+word)
  // e.g., "AirVPN GB London Alathfar" -> "GB"
  const pattern2 = /[_\s]([A-Z]{2})\s[A-Z]/;
  const match2 = baseName.match(pattern2);
  if (match2) return match2[1];

  // Pattern 3: Country code at start with separator
  // e.g., "us-server", "UK_London"
  const pattern3 = /^([a-zA-Z]{2})[-_\s]/;
  const match3 = baseName.match(pattern3);
  if (match3) return match3[1].toUpperCase();

  // Pattern 4: Known codes as whole words only
  const normalizedName = baseName.toUpperCase().replace(/[-_]/g, " ");
  for (const code of KNOWN_CODES) {
    const regex = new RegExp(`\\b${code}\\b`);
    if (regex.test(normalizedName)) {
      return code;
    }
  }

  // Fallback: first 2 characters
  return baseName.slice(0, 2).toUpperCase();
}

/**
 * Get flag emoji for country code
 */
function getFlag(countryCode: string): string {
  return FLAGS[countryCode.toLowerCase()] || "❓";
}

/**
 * Get display name from ovpn filename
 */
function getDisplayName(filepath: string): string {
  let name = basename(filepath, ".ovpn");
  // Replace dashes/underscores with spaces for readability
  name = name.replace(/-/g, " ").replace(/_/g, " ");
  return name;
}

// ============================================================================
// OpenVPN Config Parsing
// ============================================================================

/**
 * Extract server IP and port from .ovpn file content
 * Parses the `remote <host> <port>` directive
 */
async function parseOvpnFile(
  filepath: string
): Promise<{ serverIp: string; serverPort: number }> {
  try {
    const content = await readFile(filepath, "utf-8");

    // Look for "remote <host> <port>" directive
    // Can also be "remote <host> <port> <proto>"
    const remoteMatch = content.match(/^remote\s+(\S+)\s+(\d+)/m);

    if (remoteMatch) {
      return {
        serverIp: remoteMatch[1],
        serverPort: parseInt(remoteMatch[2], 10),
      };
    }

    // Fallback: try to find just "remote <host>"
    const hostOnlyMatch = content.match(/^remote\s+(\S+)/m);
    if (hostOnlyMatch) {
      return {
        serverIp: hostOnlyMatch[1],
        serverPort: 1194, // Default OpenVPN port
      };
    }

    log("WARN", `No remote directive found in ${filepath}`);
    return { serverIp: "unknown", serverPort: 1194 };
  } catch (error) {
    log("ERROR", `Failed to parse ${filepath}: ${error}`);
    return { serverIp: "unknown", serverPort: 1194 };
  }
}

// ============================================================================
// Cache Management
// ============================================================================

async function ensureStateDir(): Promise<void> {
  try {
    await mkdir(STATE_DIR, { recursive: true });
  } catch (error) {
    // Ignore if already exists
  }
}

async function loadCache(): Promise<CacheData | null> {
  try {
    const content = await readFile(CACHE_FILE, "utf-8");
    return JSON.parse(content) as CacheData;
  } catch {
    return null;
  }
}

async function saveCache(data: CacheData): Promise<void> {
  await ensureStateDir();
  await writeFile(CACHE_FILE, JSON.stringify(data, null, 2));
}

async function isCacheValid(cache: CacheData): Promise<boolean> {
  try {
    // Check if VPN directory still exists
    const dirStat = await stat(VPN_DIR);
    if (dirStat.mtimeMs !== cache.dirMtime) {
      log("DEBUG", "Cache invalid: directory mtime changed");
      return false;
    }

    // Check if any file mtime changed
    const files = await readdir(VPN_DIR);
    const ovpnFiles = files.filter((f) => f.endsWith(".ovpn"));

    // Check if file count changed
    if (ovpnFiles.length !== Object.keys(cache.filesMtime).length) {
      log("DEBUG", "Cache invalid: file count changed");
      return false;
    }

    // Check individual file mtimes
    for (const file of ovpnFiles) {
      const filepath = join(VPN_DIR, file);
      const fileStat = await stat(filepath);
      if (cache.filesMtime[filepath] !== fileStat.mtimeMs) {
        log("DEBUG", `Cache invalid: ${file} mtime changed`);
        return false;
      }
    }

    return true;
  } catch (error) {
    log("DEBUG", `Cache validation failed: ${error}`);
    return false;
  }
}

// ============================================================================
// VPN Discovery
// ============================================================================

async function discoverVpns(): Promise<VpnConfig[]> {
  log("INFO", `Discovering VPNs in ${VPN_DIR}`);

  try {
    await stat(VPN_DIR);
  } catch {
    log("WARN", `VPN directory does not exist: ${VPN_DIR}`);
    return [];
  }

  const files = await readdir(VPN_DIR);
  const ovpnFiles = files.filter((f) => f.endsWith(".ovpn")).sort();

  if (ovpnFiles.length === 0) {
    log("WARN", `No .ovpn files found in ${VPN_DIR}`);
    return [];
  }

  log("INFO", `Found ${ovpnFiles.length} VPN configs`);

  const vpns: VpnConfig[] = [];

  for (const file of ovpnFiles) {
    const filepath = join(VPN_DIR, file);
    const displayName = getDisplayName(filepath);
    const countryCode = getCountryCode(file);
    const flag = getFlag(countryCode);
    const { serverIp, serverPort } = await parseOvpnFile(filepath);

    vpns.push({
      slug: displayName, // Exact match on display name
      displayName,
      countryCode,
      flag,
      ovpnPath: filepath,
      serverIp,
      serverPort,
    });
  }

  return vpns;
}

async function buildCache(): Promise<CacheData> {
  const vpns = await discoverVpns();
  const dirStat = await stat(VPN_DIR);

  const filesMtime: Record<string, number> = {};
  for (const vpn of vpns) {
    const fileStat = await stat(vpn.ovpnPath);
    filesMtime[vpn.ovpnPath] = fileStat.mtimeMs;
  }

  const cache: CacheData = {
    vpns,
    dirMtime: dirStat.mtimeMs,
    filesMtime,
    createdAt: Date.now(),
  };

  await saveCache(cache);
  log("INFO", `Cache built with ${vpns.length} VPNs`);

  return cache;
}

// ============================================================================
// Public API
// ============================================================================

let cachedVpns: VpnConfig[] | null = null;

/**
 * Get list of all available VPNs (cached)
 */
export async function listVpns(): Promise<VpnConfig[]> {
  if (cachedVpns) {
    return cachedVpns;
  }

  const cache = await loadCache();

  if (cache && (await isCacheValid(cache))) {
    log("DEBUG", "Using cached VPN list");
    cachedVpns = cache.vpns;
    return cache.vpns;
  }

  log("INFO", "Rebuilding VPN cache");
  const newCache = await buildCache();
  cachedVpns = newCache.vpns;
  return newCache.vpns;
}

/**
 * Resolve a slug to a VPN config (exact match)
 * Returns null if not found
 */
export async function resolveVpn(slug: string): Promise<VpnConfig | null> {
  const vpns = await listVpns();

  // Exact match on display name (slug)
  const vpn = vpns.find((v) => v.slug === slug || v.displayName === slug);

  if (vpn) {
    log("INFO", `Resolved "${slug}" to ${vpn.displayName}`);
    return vpn;
  }

  log("WARN", `No VPN found for slug: "${slug}"`);
  return null;
}

/**
 * Get a random VPN config
 */
export async function getRandomVpn(): Promise<VpnConfig | null> {
  const vpns = await listVpns();

  if (vpns.length === 0) {
    log("ERROR", "No VPNs available for random selection");
    return null;
  }

  const index = Math.floor(Math.random() * vpns.length);
  const vpn = vpns[index];
  log("INFO", `Selected random VPN: ${vpn.displayName}`);
  return vpn;
}

/**
 * Get VPN server IP from an ovpn file path
 */
export async function getVpnServerIp(
  ovpnPath: string
): Promise<{ ip: string; port: number }> {
  const { serverIp, serverPort } = await parseOvpnFile(ovpnPath);
  return { ip: serverIp, port: serverPort };
}

/**
 * Invalidate the cache (force rebuild on next call)
 */
export function invalidateCache(): void {
  cachedVpns = null;
  log("INFO", "Cache invalidated");
}

// ============================================================================
// CLI Interface
// ============================================================================

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  const command = args[0];

  switch (command) {
    case "list": {
      const vpns = await listVpns();
      for (const vpn of vpns) {
        console.log(`${vpn.flag} ${vpn.displayName}`);
      }
      break;
    }

    case "list-json": {
      const vpns = await listVpns();
      console.log(JSON.stringify(vpns, null, 2));
      break;
    }

    case "resolve": {
      const slug = args.slice(1).join(" ");
      if (!slug) {
        console.error("Usage: vpn-resolver resolve <slug>");
        process.exit(1);
      }
      const vpn = await resolveVpn(slug);
      if (vpn) {
        console.log(JSON.stringify(vpn, null, 2));
      } else {
        console.error(`VPN not found: ${slug}`);
        process.exit(1);
      }
      break;
    }

    case "random": {
      const vpn = await getRandomVpn();
      if (vpn) {
        console.log(JSON.stringify(vpn, null, 2));
      } else {
        console.error("No VPNs available");
        process.exit(1);
      }
      break;
    }

    case "server-ip": {
      const ovpnPath = args[1];
      if (!ovpnPath) {
        console.error("Usage: vpn-resolver server-ip <ovpn-path>");
        process.exit(1);
      }
      const { ip, port } = await getVpnServerIp(ovpnPath);
      console.log(`${ip}:${port}`);
      break;
    }

    default:
      console.log(`VPN Resolver - SOCKS5 Proxy System

Usage:
  vpn-resolver list              List all VPNs (human readable)
  vpn-resolver list-json         List all VPNs (JSON)
  vpn-resolver resolve <slug>    Resolve slug to VPN config
  vpn-resolver random            Get a random VPN config
  vpn-resolver server-ip <path>  Get server IP from .ovpn file

Environment:
  VPN_DIR    Directory containing .ovpn files (default: ~/Shared/VPNs)
`);
  }
}

// Run CLI if executed directly
if (import.meta.main) {
  main().catch((error) => {
    log("ERROR", `Fatal error: ${error}`);
    process.exit(1);
  });
}
