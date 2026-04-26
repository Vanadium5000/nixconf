#!/usr/bin/env bun
/**
 * VPN Resolver Library
 * Provides VPN configuration parsing, caching, and slug resolution for the SOCKS5 proxy system.
 */

import { readdir, stat, readFile, mkdir, writeFile } from "fs/promises";
import { join, basename } from "path";
import { homedir } from "os";
import { loadSettings, type FieldPattern } from "./settings";

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
  /**
   * Fields extracted from the display name via pattern parsing.
   * Keys are field names (e.g., "country", "city", "server"),
   * values are the extracted strings. Populated lazily by parseVpnFields().
   */
  parsedFields?: Record<string, string>;
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
const STATE_DIR = `/dev/shm/vpn-proxy-${process.getuid!()}`;
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

// Shared/VPNs/openvpn contains full country-name basenames alongside AirVPN-style
// ISO-prefixed names, so basename-only parsing needs explicit mappings for names
// that cannot be derived from the first two characters.
const COUNTRY_NAME_TO_CODE: Record<string, string> = {
  albania: "AL",
  algeria: "DZ",
  andorra: "AD",
  argentina: "AR",
  armenia: "AM",
  australia: "AU",
  austria: "AT",
  bahamas: "BS",
  bangladesh: "BD",
  belgium: "BE",
  bolivia: "BO",
  bosnia_and_herzegovina: "BA",
  brazil: "BR",
  bulgaria: "BG",
  cambodia: "KH",
  chile: "CL",
  china: "CN",
  colombia: "CO",
  costa_rica: "CR",
  croatia: "HR",
  cyprus: "CY",
  czech_republic: "CZ",
  ecuador: "EC",
  egypt: "EG",
  estonia: "EE",
  france: "FR",
  georgia: "GE",
  greece: "GR",
  greenland: "GL",
  guatemala: "GT",
  hong_kong: "HK",
  hungary: "HU",
  iceland: "IS",
  india: "IN",
  indonesia: "ID",
  ireland: "IE",
  isle_of_man: "IM",
  israel: "IL",
  kazakhstan: "KZ",
  latvia: "LV",
  liechtenstein: "LI",
  lithuania: "LT",
  luxembourg: "LU",
  macao: "MO",
  malaysia: "MY",
  malta: "MT",
  mexico: "MX",
  moldova: "MD",
  monaco: "MC",
  mongolia: "MN",
  montenegro: "ME",
  morocco: "MA",
  nepal: "NP",
  netherlands: "NL",
  new_zealand: "NZ",
  nigeria: "NG",
  north_macedonia: "MK",
  norway: "NO",
  panama: "PA",
  peru: "PE",
  philippines: "PH",
  poland: "PL",
  portugal: "PT",
  qatar: "QA",
  romania: "RO",
  saudi_arabia: "SA",
  serbia: "RS",
  singapore: "SG",
  slovakia: "SK",
  slovenia: "SI",
  south_africa: "ZA",
  south_korea: "KR",
  sri_lanka: "LK",
  switzerland: "CH",
  taiwan: "TW",
  turkey: "TR",
  ukraine: "UA",
  united_arab_emirates: "AE",
  uruguay: "UY",
  venezuela: "VE",
  vietnam: "VN",
};

const NON_LOCATION_SUFFIXES = ["streaming", "optimized"];

// ============================================================================
// Logging
// ============================================================================

function log(
  level: "DEBUG" | "INFO" | "WARN" | "ERROR",
  message: string,
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
function getBasenameTokens(filename: string): string[] {
  return basename(filename, ".ovpn")
    .split(/[-_\s]+/)
    .filter(Boolean);
}

function getCountryCodeFromLeadingToken(tokens: string[]): string | null {
  const [firstToken] = tokens;
  if (!firstToken || !/^[a-zA-Z]{2}$/.test(firstToken)) {
    return null;
  }

  return firstToken.toUpperCase();
}

function getCountryCodeFromKnownWords(baseName: string): string | null {
  const normalizedName = baseName.toUpperCase().replace(/[-_]/g, " ");
  for (const code of KNOWN_CODES) {
    const regex = new RegExp(`\\b${code}\\b`);
    if (regex.test(normalizedName)) {
      return code;
    }
  }

  return null;
}

function getCountryCodeFromCountryName(tokens: string[]): string | null {
  const trimmedTokens = [...tokens];
  while (
    trimmedTokens.length > 0 &&
    NON_LOCATION_SUFFIXES.includes(
      trimmedTokens[trimmedTokens.length - 1]!.toLowerCase(),
    )
  ) {
    trimmedTokens.pop();
  }

  const fullName = trimmedTokens.join("_").toLowerCase();
  return COUNTRY_NAME_TO_CODE[fullName] ?? null;
}

function getCountryCode(filename: string): string {
  const baseName = basename(filename, ".ovpn");
  const tokens = getBasenameTokens(filename);

  // Pattern 1: Standalone 2-letter code surrounded by separators
  // e.g., "AirVPN_AT_Vienna" or "AirVPN AT Vienna" -> "AT"
  const pattern1 = /[_\s]([A-Z]{2})[_\s]/;
  const match1 = baseName.match(pattern1);
  if (match1) return match1[1]!;

  // Pattern 2: "Provider CC City" format (code followed by space+word)
  // e.g., "AirVPN GB London Alathfar" -> "GB"
  const pattern2 = /[_\s]([A-Z]{2})\s[A-Z]/;
  const match2 = baseName.match(pattern2);
  if (match2) return match2[1]!;

  // Leading provider tokens need to win before whole-word scans so
  // filenames like "nl_netherlands_streaming_optimized" stay tied to "nl".
  const leadingTokenCode = getCountryCodeFromLeadingToken(tokens);
  if (leadingTokenCode) return leadingTokenCode;

  // Pattern 4: Known codes as whole words only
  const knownWordCode = getCountryCodeFromKnownWords(baseName);
  if (knownWordCode) return knownWordCode;

  // Pattern 5: Full country-name basenames from the local OpenVPN corpus.
  const countryNameCode = getCountryCodeFromCountryName(tokens);
  if (countryNameCode) return countryNameCode;

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

/**
 * Generate slug from display name (spaces removed for easier usage)
 */
function generateSlug(displayName: string): string {
  return displayName.replace(/\s+/g, "");
}

/**
 * Normalize a slug for comparison (strip all whitespace)
 */
function normalizeSlug(slug: string): string {
  return slug.replace(/\s+/g, "");
}

// ============================================================================
// OpenVPN Config Parsing
// ============================================================================

/**
 * Extract server IP and port from .ovpn file content
 * Parses the `remote <host> <port>` directive
 */
async function parseOvpnFile(
  filepath: string,
): Promise<{ serverIp: string; serverPort: number }> {
  try {
    const content = await readFile(filepath, "utf-8");

    // Look for "remote <host> <port>" directive
    // Can also be "remote <host> <port> <proto>"
    const remoteMatch = content.match(/^remote\s+(\S+)\s+(\d+)/m);

    if (remoteMatch) {
      return {
        serverIp: remoteMatch[1]!,
        serverPort: parseInt(remoteMatch[2]!, 10),
      };
    }

    // Fallback: try to find just "remote <host>"
    const hostOnlyMatch = content.match(/^remote\s+(\S+)/m);
    if (hostOnlyMatch) {
      return {
        serverIp: hostOnlyMatch[1]!,
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
    const ovpnFiles = await findOvpnFilesRecursive(VPN_DIR);

    if (ovpnFiles.length !== Object.keys(cache.filesMtime).length) {
      log("DEBUG", "Cache invalid: file count changed");
      return false;
    }

    for (const filepath of ovpnFiles) {
      const fileStat = await stat(filepath);
      if (cache.filesMtime[filepath] !== fileStat.mtimeMs) {
        log("DEBUG", `Cache invalid: ${basename(filepath)} mtime changed`);
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

/**
 * Recursively find all .ovpn files in a directory
 */
async function findOvpnFilesRecursive(dir: string): Promise<string[]> {
  const results: string[] = [];

  try {
    const entries = await readdir(dir, { withFileTypes: true });

    for (const entry of entries) {
      const fullPath = join(dir, entry.name);

      if (entry.isDirectory()) {
        const subFiles = await findOvpnFilesRecursive(fullPath);
        results.push(...subFiles);
      } else if (entry.isFile() && entry.name.endsWith(".ovpn")) {
        results.push(fullPath);
      }
    }
  } catch (error) {
    log("WARN", `Failed to read directory ${dir}: ${error}`);
  }

  return results;
}

async function discoverVpns(): Promise<VpnConfig[]> {
  log("INFO", `Discovering VPNs in ${VPN_DIR} (recursive)`);

  try {
    await stat(VPN_DIR);
  } catch {
    log("WARN", `VPN directory does not exist: ${VPN_DIR}`);
    return [];
  }

  const ovpnFiles = (await findOvpnFilesRecursive(VPN_DIR)).sort();

  if (ovpnFiles.length === 0) {
    log("WARN", `No .ovpn files found in ${VPN_DIR} or subdirectories`);
    return [];
  }

  log("INFO", `Found ${ovpnFiles.length} VPN configs`);

  const vpns: VpnConfig[] = [];

  for (const filepath of ovpnFiles) {
    const displayName = getDisplayName(filepath);
    const countryCode = getCountryCode(basename(filepath));
    const flag = getFlag(countryCode);
    const { serverIp, serverPort } = await parseOvpnFile(filepath);

    vpns.push({
      slug: generateSlug(displayName), // Space-free slug for easier usage
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
// Pattern-Based VPN Matching
// ============================================================================

/**
 * Extract named fields from a VPN display name using the configured patterns.
 * For "AirVPN GB Manchester Ceibo UDP 443 Entry3" with default patterns:
 *   → { country: "GB", city: "Manchester", server: "Ceibo" }
 */
export function parseVpnFields(
  displayName: string,
  fieldPatterns: FieldPattern[],
): Record<string, string> {
  const fields: Record<string, string> = {};

  for (const pattern of fieldPatterns) {
    try {
      const match = displayName.match(new RegExp(pattern.regex));
      if (match && match[pattern.position]) {
        fields[pattern.name] = match[pattern.position]!;
      }
    } catch {
      log(
        "WARN",
        `Invalid regex in field pattern "${pattern.name}": ${pattern.regex}`,
      );
    }
  }

  return fields;
}

/**
 * Ensure all VPNs have their parsedFields populated.
 * Called lazily on first pattern match attempt.
 */
async function ensureParsedFields(vpns: VpnConfig[]): Promise<void> {
  const settings = await loadSettings();
  if (!settings.patternParsing.enabled) return;

  for (const vpn of vpns) {
    if (!vpn.parsedFields) {
      vpn.parsedFields = parseVpnFields(
        vpn.displayName,
        settings.patternParsing.fieldPatterns,
      );
    }
  }
}

/**
 * Check if a search term should be excluded from pattern matching.
 * Prevents matching against provider names, protocols, ports, etc.
 */
function isExcludedPattern(term: string, excludePatterns: string[]): boolean {
  return excludePatterns.some((pattern) => {
    try {
      return new RegExp(`^${pattern}$`, "i").test(term);
    } catch {
      return false;
    }
  });
}

/**
 * Resolve a pattern/partial name to matching VPN configs.
 * Matches the input against all parsed fields of all VPNs.
 * Case-insensitive. Returns all matches (caller picks or errors).
 *
 * @example resolveVpnByPattern("GB") → all UK VPNs
 * @example resolveVpnByPattern("Manchester") → VPNs in Manchester
 * @example resolveVpnByPattern("Ceibo") → the specific Ceibo server
 */
export async function resolveVpnByPattern(
  pattern: string,
): Promise<VpnConfig[]> {
  const settings = await loadSettings();
  if (!settings.patternParsing.enabled) return [];

  if (isExcludedPattern(pattern, settings.patternParsing.excludePatterns)) {
    log("DEBUG", `Pattern "${pattern}" is excluded from matching`);
    return [];
  }

  const vpns = await listVpns();
  await ensureParsedFields(vpns);

  const normalizedPattern = pattern.toLowerCase();
  const matches: VpnConfig[] = [];

  for (const vpn of vpns) {
    if (!vpn.parsedFields) continue;

    for (const value of Object.values(vpn.parsedFields)) {
      if (value.toLowerCase() === normalizedPattern) {
        matches.push(vpn);
        break; // One match per VPN is enough
      }
    }
  }

  if (matches.length > 0) {
    log("INFO", `Pattern "${pattern}" matched ${matches.length} VPN(s)`);
  }

  return matches;
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
 * Resolve a slug to a VPN config.
 * Tries exact match first, then pattern-based matching (picks random from matches).
 */
export async function resolveVpn(slug: string): Promise<VpnConfig | null> {
  const vpns = await listVpns();
  const normalizedInput = normalizeSlug(slug);

  const vpn = vpns.find((v) => v.slug === normalizedInput);
  if (vpn) {
    log("INFO", `Resolved "${slug}" to ${vpn.displayName}`);
    return vpn;
  }

  // Pattern matching: "GB" → random UK VPN, "Ceibo" → specific server
  const patternMatches = await resolveVpnByPattern(slug);
  if (patternMatches.length > 0) {
    const picked =
      patternMatches[Math.floor(Math.random() * patternMatches.length)]!;
    log(
      "INFO",
      `Pattern "${slug}" matched ${patternMatches.length} VPN(s), picked ${picked.displayName}`,
    );
    return picked;
  }

  log("WARN", `No VPN found for slug: "${slug}"`);
  return null;
}

/**
 * Get a random VPN config.
 * @param excludeSlugs Slugs to exclude (e.g., failed test results)
 */
export async function getRandomVpn(
  excludeSlugs?: Set<string>,
): Promise<VpnConfig | null> {
  const vpns = await listVpns();

  const candidates = excludeSlugs
    ? vpns.filter((v) => !excludeSlugs.has(v.slug))
    : vpns;

  if (candidates.length === 0) {
    // Fall back to full list if all are excluded
    if (excludeSlugs && vpns.length > 0) {
      log("WARN", "All VPNs excluded by filter, using unfiltered list");
      const index = Math.floor(Math.random() * vpns.length);
      return vpns[index]!;
    }
    log("ERROR", "No VPNs available for random selection");
    return null;
  }

  const index = Math.floor(Math.random() * candidates.length);
  const vpn = candidates[index]!;
  log("INFO", `Selected random VPN: ${vpn.displayName}`);
  return vpn;
}

/**
 * Get VPN server IP from an ovpn file path
 */
export async function getVpnServerIp(
  ovpnPath: string,
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

/**
 * Check if a slug is a valid VPN name or pattern match.
 * Accepts exact slug matches AND pattern-based matches (e.g., "GB", "Manchester").
 */
export async function isValidSlug(slug: string): Promise<boolean> {
  if (!slug || slug === "random" || slug === "none") return true;
  const vpns = await listVpns();
  const normalizedInput = normalizeSlug(slug);

  if (vpns.some((v) => v.slug === normalizedInput)) return true;

  const patternMatches = await resolveVpnByPattern(slug);
  return patternMatches.length > 0;
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

    case "match": {
      const pattern = args.slice(1).join(" ");
      if (!pattern) {
        console.error("Usage: vpn-resolver match <pattern>");
        process.exit(1);
      }
      const matches = await resolveVpnByPattern(pattern);
      if (matches.length === 0) {
        console.error(`No VPNs match pattern: ${pattern}`);
        process.exit(1);
      }
      console.log(JSON.stringify(matches, null, 2));
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
  vpn-resolver match <pattern>   Find VPNs matching a pattern (country/city/server)
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
