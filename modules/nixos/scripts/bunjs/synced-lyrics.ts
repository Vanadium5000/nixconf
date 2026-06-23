#!/usr/bin/env bun
// lyricsctl - synced lyrics fetcher, shell widget JSON source, and terminal UI
import { $ } from "bun";
import { mkdir } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";

// --- Configuration ---
const CACHE_DIR = join(tmpdir(), "synced-lyrics-cache");
const CACHE_VERSION = 2;
const DEFAULT_PLAYER = "mpd,%any";
const LRCLIB_API = "https://lrclib.net/api";
const LRCCX_API = "https://api.lrc.cx/lyrics";
const USER_AGENT = "lyricsctl/1.0";

// --- Types ---
interface TrackMetadata {
  title: string;
  artist: string;
  album: string;
  duration: number; // in seconds
  position: number; // in seconds
  status: "Playing" | "Paused" | "Stopped";
  player: string;
  capturedAtMs: number;
}

interface LyricLine {
  time: number; // in seconds
  text: string;
}

interface TimedLyricLine extends LyricLine {
  current: boolean;
}

interface LyricsData {
  synced: boolean;
  lines: LyricLine[];
  plainText?: string;
  source?: string;
  cacheVersion?: number;
}

interface PlayerSource {
  id: string;
  name: string;
  current: boolean;
}

interface LyricsWidgetOutput {
  text: string;
  tooltip: string;
  class: string;
  alt: string;
  title: string;
  artist: string;
  album: string;
  player: string;
  status: TrackMetadata["status"] | "Stopped";
  position: number;
  duration: number;
  synced: boolean;
  current: string;
  upcoming: string[];
  lines: string[];
  timedLines: TimedLyricLine[];
  currentIndex: number;
  nextLineTime: number | null;
  nextChangeInMs: number;
  generatedAtMs: number;
  source: string;
}

// --- CLI Parsing ---
interface CliOptions {
  command: "watch" | "current" | "status" | "lookup" | "sources" | "show" | "hide" | "toggle" | "control" | "seek" | "tui";
  controlAction: "play-pause" | "play" | "pause" | "next" | "previous" | "stop";
  seekPosition: number;
  lookupTitle: string;
  lookupArtist: string;
  lookupAlbum: string;
  lookupDuration: number;
  json: boolean;
  progress: boolean;
  lines: number;
  player: string;
  quiet: boolean;
  // Overlay options
  length: number;
  fontSize: number;
  color: string;
  position: string;
  opacity: number;
  shadow: boolean;
  spacing: number;
}

function parseArgs(): CliOptions {
  const args = Bun.argv.slice(2);
  const options: CliOptions = {
    command: "watch",
    controlAction: "play-pause",
    seekPosition: 0,
    lookupTitle: "",
    lookupArtist: "",
    lookupAlbum: "",
    lookupDuration: 0,
    json: false,
    progress: false,
    lines: 3,
    player: DEFAULT_PLAYER,
    quiet: false,
    length: 0,
    fontSize: 28,
    color: "#ffffff",
    position: "bottom",
    opacity: 0.95,
    shadow: true,
    spacing: 8,
  };

  let i = 0;
  while (i < args.length) {
    const arg = args[i];

    // Commands and command arguments.
    if (!arg?.startsWith("-")) {
      if (["watch", "current", "status", "lookup", "sources", "show", "hide", "toggle", "control", "seek", "tui"].includes(arg!)) {
        options.command = arg as CliOptions["command"];
      } else if (options.command === "control" && ["play-pause", "play", "pause", "next", "previous", "stop"].includes(arg!)) {
        options.controlAction = arg as CliOptions["controlAction"];
      } else if (options.command === "seek") {
        options.seekPosition = Math.max(0, parseFloat(arg!) || 0);
      }
      i++;
      continue;
    }

    switch (arg) {
      case "--json":
      case "-j":
        options.json = true;
        break;
      case "--progress":
      case "-p":
        options.progress = true;
        break;
      case "--lines":
      case "-l":
        i++;
        options.lines = Math.max(1, parseInt(args[i] || "3") || 3);
        break;
      case "--length":
      case "-len":
        i++;
        options.length = parseInt(args[i] || "0") || 0;
        break;
      case "--font-size":
        i++;
        options.fontSize = parseInt(args[i] || "28") || 28;
        break;
      case "--color":
        i++;
        options.color = args[i] || "#ffffff";
        break;
      case "--position":
        i++;
        options.position = args[i] || "bottom";
        break;
      case "--opacity":
        i++;
        options.opacity = parseFloat(args[i] || "0.95") || 0.95;
        break;
      case "--shadow":
        i++;
        options.shadow = args[i] === "false" ? false : true;
        break;
      case "--spacing":
        i++;
        options.spacing = parseInt(args[i] || "8") || 8;
        break;
      case "--player":
        i++;
        options.player = args[i] || DEFAULT_PLAYER;
        break;
      case "--title":
        i++;
        options.lookupTitle = args[i] || "";
        break;
      case "--artist":
        i++;
        options.lookupArtist = args[i] || "";
        break;
      case "--album":
        i++;
        options.lookupAlbum = args[i] || "";
        break;
      case "--duration":
        i++;
        options.lookupDuration = Math.max(0, parseFloat(args[i] || "0") || 0);
        break;
      case "--quiet":
      case "-q":
        options.quiet = true;
        break;
      case "--help":
      case "-h":
        console.log(`
lyricsctl - Display synced lyrics for currently playing music

Commands:
  watch           Continuous output for shell widgets (default)
  current         Print current lyric line once
  status          Print one JSON status object with metadata and lyrics context
  lookup          Fetch lyrics for --title/--artist/--duration without a player
  sources         Print available player sources as JSON
  control ACTION  Run player control: play-pause, play, pause, next, previous, stop
  seek SECONDS    Seek current player to absolute song position
  tui             Terminal lyrics view with keyboard controls
  show            Show lyrics overlay
  hide            Hide lyrics overlay  
  toggle          Toggle lyrics overlay

Options:
  --json, -j      Output JSON for shell widgets
  --progress, -p  Show progress/timestamp
  --lines N, -l N Number of lines to display (default: 3)
  --length N      Max line length before truncation (default: 0, disabled)
  --player NAME   Player to use (default: mpd,%any)
  --title TEXT    Lookup title for the lookup command
  --artist TEXT   Lookup artist for the lookup command
  --album TEXT    Lookup album for the lookup command
  --duration N    Lookup duration in seconds
  --quiet, -q     Suppress errors
  
Overlay Options:
  --font-size N   Font size for overlay (default: 28)
  --color HEX     Text color (default: #ffffff)
  --position POS  Overlay position: top, bottom, center (default: bottom)
  --opacity N     Text opacity (0.0-1.0, default: 0.95)
  --shadow BOOL   Show text shadow/outline (default: true)
  --spacing N     Spacing between lines (default: 8)
  --help, -h      Show this help

TUI Keys:
  Space play/pause · n next · p previous · o toggle overlay · h hide overlay · q quit
`);
        process.exit(0);
    }
    i++;
  }

  return options;
}

function stoppedOutput(tooltip: string): LyricsWidgetOutput {
  return {
    text: "",
    tooltip,
    class: "stopped",
    alt: "stopped",
    title: "",
    artist: "",
    album: "",
    player: "",
    status: "Stopped",
    position: 0,
    duration: 0,
    synced: false,
    current: "",
    upcoming: [],
    lines: [],
    timedLines: [],
    currentIndex: -1,
    nextLineTime: null,
    nextChangeInMs: 1000,
    generatedAtMs: Date.now(),
    source: "",
  };
}

// --- Playerctl Integration ---
async function getMetadata(player: string): Promise<TrackMetadata | null> {
  try {
    const startedAtMs = Date.now();
    // Use separate calls to avoid format string escaping issues
    const [title, artist, album, length, position, status, playerName] =
      await Promise.all([
        $`playerctl --player=${player} metadata title`.text().catch(() => ""),
        $`playerctl --player=${player} metadata artist`.text().catch(() => ""),
        $`playerctl --player=${player} metadata album`.text().catch(() => ""),
        $`playerctl --player=${player} metadata mpris:length`
          .text()
          .catch(() => "0"),
        $`playerctl --player=${player} position`.text().catch(() => "0"),
        $`playerctl --player=${player} status`.text().catch(() => "Stopped"),
        $`playerctl --player=${player} metadata --format '{{playerName}}'`
          .text()
          .catch(() => ""),
      ]);

    const titleTrimmed = title.trim();
    if (!titleTrimmed) return null;

    // mpris:length is in microseconds, position from `playerctl position` is in seconds
    const lengthUs = parseInt(length.trim()) || 0;
    const positionSec = parseFloat(position.trim()) || 0;

    return {
      title: titleTrimmed,
      artist: artist.trim(),
      album: album.trim(),
      duration: lengthUs / 1_000_000,
      position: positionSec,
      status: (status.trim() as TrackMetadata["status"]) || "Stopped",
      player: playerName.trim(),
      capturedAtMs: Math.round((startedAtMs + Date.now()) / 2),
    };
  } catch {
    return null;
  }
}

async function listPlayerSources(player: string): Promise<PlayerSource[]> {
  const current = player.trim() || DEFAULT_PLAYER;
  const sources: PlayerSource[] = [{ id: DEFAULT_PLAYER, name: "Default", current: current === DEFAULT_PLAYER }];

  try {
    const output = await $`playerctl -l`.text();
    const seen = new Set<string>([DEFAULT_PLAYER]);
    for (const line of output.split("\n")) {
      const id = line.trim();
      if (!id || seen.has(id)) continue;
      seen.add(id);
      sources.push({ id, name: id, current: id === current });
    }
  } catch { }

  return sources;
}

// --- Title Normalization ---
function normalizeTitle(title: string): string {
  return (
    title
      // Remove common suffixes
      .replace(/\s*\(Official\s*(Music\s*)?Video\)/gi, "")
      .replace(/\s*\(Official\s*Audio\)/gi, "")
      .replace(/\s*\(Lyric\s*Video\)/gi, "")
      .replace(/\s*\(Lyrics?\)/gi, "")
      .replace(/\s*\[Official\s*(Music\s*)?Video\]/gi, "")
      .replace(/\s*\[Official\s*Audio\]/gi, "")
      .replace(/\s*\[Lyric\s*Video\]/gi, "")
      .replace(/\s*\[Lyrics?\]/gi, "")
      // Remove featuring artists
      .replace(/\s*\(feat\.?\s*[^)]+\)/gi, "")
      .replace(/\s*\(ft\.?\s*[^)]+\)/gi, "")
      .replace(/\s*feat\.?\s*.+$/gi, "")
      .replace(/\s*ft\.?\s*.+$/gi, "")
      // Remove remaster/remix info
      .replace(/\s*\(Remaster(ed)?\s*\d*\)/gi, "")
      .replace(/\s*-\s*Remaster(ed)?\s*\d*/gi, "")
      // Remove year (e.g. (1966))
      .replace(/\s*\(\d{4}\)/g, "")
      // Clean up
      .replace(/\s+/g, " ")
      .trim()
  );
}

function normalizeArtist(artist: string): string {
  // Take first artist if multiple
  return artist.split(/[,&]/)[0]!.replace(/\s+/g, " ").trim();
}

function lyricTextToSyncedData(text: string | null | undefined): LyricsData | null {
  if (!text) return null;
  const lines = parseLrc(text);
  return lines.length > 0 ? { synced: true, lines } : null;
}

function lyricTextToPlainData(text: string | null | undefined): LyricsData | null {
  return text ? { synced: false, lines: [], plainText: text } : null;
}

function normalizedKey(value: string): string {
  return normalizeTitle(value).toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
}

function scoreLrclibResult(result: any, title: string, artist: string, duration: number): number {
  const titleScore = normalizedKey(result.trackName || result.name || "") === normalizedKey(title) ? 0 : 20;
  const artistScore = normalizedKey(result.artistName || "") === normalizedKey(artist) ? 0 : 20;
  const durationScore = Number.isFinite(Number(result.duration)) ? Math.min(60, Math.abs(Number(result.duration) - duration)) : 30;
  return titleScore + artistScore + durationScore;
}

// --- LRCLIB API ---
async function fetchFromLrclib(
  title: string,
  artist: string,
  album: string,
  duration: number,
): Promise<LyricsData | null> {
  const headers = { "User-Agent": USER_AGENT };
  let bestPlain: LyricsData | null = null;

  async function getByParams(trackName: string, artistName: string, albumName?: string): Promise<LyricsData | null> {
    const params = new URLSearchParams({
      track_name: trackName,
      artist_name: artistName,
      duration: duration.toString(),
    });
    if (albumName) params.set("album_name", albumName);

    try {
      const response = await fetch(`${LRCLIB_API}/get?${params}`, { headers });
      if (!response.ok) return null;
      const data = (await response.json()) as any;
      const synced = lyricTextToSyncedData(data.syncedLyrics);
      if (synced) return { ...synced, source: "lrclib/get", cacheVersion: CACHE_VERSION };
      const plain = lyricTextToPlainData(data.plainLyrics);
      if (plain && !bestPlain) bestPlain = { ...plain, source: "lrclib/get", cacheVersion: CACHE_VERSION };
    } catch { }
    return null;
  }

  // Try exact match first
  const exact = await getByParams(title, artist, album);
  if (exact) return exact;

  // Try normalized title
  const normTitle = normalizeTitle(title);
  const normArtist = normalizeArtist(artist);

  if (normTitle !== title || normArtist !== artist) {
    const normalized = await getByParams(normTitle, normArtist);
    if (normalized) return normalized;
  }

  // Try parsing "Artist - Title" from title (common in some files)
  if (title.includes(" - ")) {
    const parts = title.split(" - ");
    if (parts.length >= 2) {
      const extractedArtist = parts[0]!.trim();
      const extractedTitle = parts.slice(1).join(" - ").trim();
      const normExtTitle = normalizeTitle(extractedTitle);

      const extracted = await getByParams(normExtTitle, extractedArtist);
      if (extracted) return extracted;
    }
  }

  // Try search as fallback
  try {
    const query = `${normArtist} ${normTitle}`;
    const response = await fetch(
      `${LRCLIB_API}/search?q=${encodeURIComponent(query)}`,
      { headers },
    );

    if (response.ok) {
      const results = (await response.json()) as any[];

      const sorted = results
        .filter((r) => normalizedKey(r.trackName || r.name || "").includes(normalizedKey(normTitle)) || normalizedKey(normTitle).includes(normalizedKey(r.trackName || r.name || "")))
        .sort((a, b) => scoreLrclibResult(a, title, artist, duration) - scoreLrclibResult(b, title, artist, duration));

      for (const match of sorted.length > 0 ? sorted : results) {
        const synced = lyricTextToSyncedData(match?.syncedLyrics);
        if (synced) return { ...synced, source: "lrclib/search", cacheVersion: CACHE_VERSION };
        const plain = lyricTextToPlainData(match?.plainLyrics);
        if (plain && !bestPlain) bestPlain = { ...plain, source: "lrclib/search", cacheVersion: CACHE_VERSION };
      }
    }
  } catch { }

  return bestPlain;
}

async function fetchFromLrcCx(title: string, artist: string): Promise<LyricsData | null> {
  const attempts = [
    { title, artist },
    { title: normalizeTitle(title), artist: normalizeArtist(artist) },
  ];

  for (const attempt of attempts) {
    try {
      const params = new URLSearchParams({
        title: attempt.title,
        artist: attempt.artist,
      });
      const response = await fetch(`${LRCCX_API}?${params}`, {
        headers: { "User-Agent": USER_AGENT },
      });
      if (!response.ok) continue;
      const text = await response.text();
      const synced = lyricTextToSyncedData(text);
      if (synced) return { ...synced, source: "lrc.cx", cacheVersion: CACHE_VERSION };
    } catch { }
  }

  return null;
}

async function fetchLyricsFromSources(
  title: string,
  artist: string,
  album: string,
  duration: number,
): Promise<LyricsData | null> {
  const lrclib = await fetchFromLrclib(title, artist, album, duration);
  if (lrclib?.synced) return lrclib;

  const lrcCx = await fetchFromLrcCx(title, artist);
  if (lrcCx?.synced) return lrcCx;

  return lrclib;
}

// --- LRC Parsing ---
function parseLrc(lrcText: string): LyricLine[] {
  const lines: LyricLine[] = [];
  const lineRegex = /\[(\d{1,2}):(\d{2})[.:](\d{2,3})\]\s*/g;

  for (const line of lrcText.split("\n")) {
    const matches = Array.from(line.matchAll(lineRegex));
    if (matches.length > 0) {
      const text = line.replace(lineRegex, "").trim();
      if (!text) continue;

      for (const match of matches) {
        const minutes = parseInt(match[1]!);
        const seconds = parseInt(match[2]!);
        const ms = parseInt(match[3]!.padEnd(3, "0"));
        lines.push({
          time: minutes * 60 + seconds + ms / 1000,
          text,
        });
      }
    }
  }

  return lines.sort((a, b) => a.time - b.time);
}

// --- Lyrics Sync ---
function getCurrentLines(
  lyrics: LyricsData,
  position: number,
  numLines: number,
): { current: string; upcoming: string[]; previous: string[]; index: number } {
  if (!lyrics.synced || lyrics.lines.length === 0) {
    return { current: "", upcoming: [], previous: [], index: -1 };
  }

  // Binary search for current line. Keep -1 before the first timestamp so the
  // UI can show a neutral placeholder instead of incorrectly marking line 0 as
  // already current.
  let left = 0;
  let right = lyrics.lines.length - 1;
  let currentIndex = -1;

  while (left <= right) {
    const mid = Math.floor((left + right) / 2);
    if (lyrics.lines[mid]!.time <= position) {
      currentIndex = mid;
      left = mid + 1;
    } else {
      right = mid - 1;
    }
  }

  const current = currentIndex >= 0 ? (lyrics.lines[currentIndex]?.text || "") : "";
  const upcoming: string[] = [];
  const previous: string[] = [];

  if (currentIndex > 0) {
    for (let i = Math.max(0, currentIndex - 5); i < currentIndex; i++) {
      previous.push(lyrics.lines[i]!.text);
    }
  }

  const start = currentIndex >= 0 ? currentIndex + 1 : 0;
  for (let i = start; upcoming.length < Math.max(0, numLines - 1) && i < lyrics.lines.length; i++) {
    upcoming.push(lyrics.lines[i]!.text);
  }

  return { current, upcoming, previous, index: currentIndex };
}

// --- Caching ---
function getCacheKey(metadata: TrackMetadata): string {
  const clean = (s: string) => s.replace(/[^a-zA-Z0-9]/g, "_").toLowerCase();
  return `${clean(metadata.artist)}-${clean(metadata.title)}-${Math.round(metadata.duration)
    }.lrc`;
}

async function getCachedLyrics(
  metadata: TrackMetadata,
): Promise<LyricsData | null> {
  try {
    const cacheFile = join(CACHE_DIR, getCacheKey(metadata));
    const file = Bun.file(cacheFile);
    if (await file.exists()) {
      const content = await file.text();
      const data = JSON.parse(content);
      const lyrics = data as LyricsData;
      if (lyrics.cacheVersion !== CACHE_VERSION || !lyrics.synced) return null;
      return lyrics;
    }
  } catch { }
  return null;
}

async function cacheLyrics(
  metadata: TrackMetadata,
  lyrics: LyricsData,
): Promise<void> {
  try {
    await mkdir(CACHE_DIR, { recursive: true });
    const cacheFile = join(CACHE_DIR, getCacheKey(metadata));
    await Bun.write(cacheFile, JSON.stringify(lyrics));
  } catch { }
}

async function loadLyrics(metadata: TrackMetadata): Promise<LyricsData | null> {
  const cached = await getCachedLyrics(metadata);
  if (cached) return cached;

  const fetched = await fetchLyricsFromSources(
    metadata.title,
    metadata.artist,
    metadata.album,
    Math.round(metadata.duration),
  );

  if (fetched) await cacheLyrics(metadata, fetched);
  return fetched;
}

// --- Output Formatting ---
function truncate(text: string, length: number): string {
  if (length <= 0 || text.length <= length) return text;
  return text.slice(0, length - 3) + "...";
}

function formatProgress(position: number, duration: number): string {
  const formatTime = (s: number) => {
    const m = Math.floor(s / 60);
    const sec = Math.floor(s % 60);
    return `${m}:${sec.toString().padStart(2, "0")}`;
  };
  return `[${formatTime(position)}/${formatTime(duration)}]`;
}

function formatLyricsWidgetOutput(
  metadata: TrackMetadata | null,
  lyrics: LyricsData | null,
  options: CliOptions,
): LyricsWidgetOutput {
  if (!metadata) {
    return stoppedOutput("No player active");
  }

  const generatedAtMs = Date.now();
  const effectivePosition = metadata.status === "Playing"
    ? metadata.position + Math.max(0, generatedAtMs - metadata.capturedAtMs) / 1000
    : metadata.position;

  const { current, upcoming, previous, index: currentIndex } = lyrics?.synced
    ? getCurrentLines(lyrics, effectivePosition, options.lines)
    : { current: "", upcoming: [], previous: [], index: -1 };
  const nextLineTime =
    lyrics?.synced
      ? (lyrics.lines[currentIndex + 1]?.time ?? null)
      : null;
  const nextChangeInMs =
    metadata.status === "Playing" && nextLineTime !== null
      ? Math.max(80, Math.round((nextLineTime - effectivePosition) * 1000))
      : 1000;
  const plainLines = lyrics?.plainText
    ? lyrics.plainText
      .split("\n")
      .map((line) => truncate(line.trim(), options.length))
      .filter(Boolean)
      .slice(0, options.lines)
    : [];
  const displayLines = lyrics?.synced
    ? [...previous, current || "♪", ...upcoming].map((line) => truncate(line, options.length))
    : plainLines;
  const timedLines = lyrics?.synced
    ? lyrics.lines
      .slice(
        currentIndex >= 0 ? Math.max(0, currentIndex - 5) : 0,
        (currentIndex >= 0 ? currentIndex : 0) + options.lines,
      )
      .map((line) => ({
        time: line.time,
        text: truncate(line.text, options.length),
        current: currentIndex >= 0 && line.time === lyrics.lines[currentIndex]?.time,
      }))
    : [];

  // If no lyrics found (or only plain text), fallback to title
  // If synced lyrics exist but we're in a gap, show ♪
  const fallbackText = lyrics?.synced ? "♪" : metadata.title;
  let text = truncate(current || fallbackText, options.length);

  if (options.progress && metadata.duration > 0) {
    text = `${formatProgress(metadata.position, metadata.duration)} ${text}`;
  }

  // Build tooltip with context
  let tooltip = `<b>${truncate(metadata.title, options.length)}</b>\n${truncate(
    metadata.artist,
    options.length,
  )}`;
  if (metadata.album)
    tooltip += `\n<i>${truncate(metadata.album, options.length)}</i>`;
  tooltip += "\n";

  if (lyrics?.synced && current) {
    tooltip += `\n<b>► ${truncate(current, options.length)}</b>`;
    for (const line of upcoming) {
      tooltip += `\n  ${truncate(line, options.length)}`;
    }
  } else if (lyrics?.plainText) {
    const previewLines = lyrics.plainText
      .split("\n")
      .slice(0, 8)
      .map((l) => truncate(l, options.length))
      .join("\n");
    tooltip += `\n${previewLines}...`;
  } else {
    tooltip += "\n<i>No lyrics found</i>";
  }

  const statusClass =
    metadata.status === "Playing"
      ? lyrics?.synced
        ? "playing"
        : "no-lyrics"
      : "paused";

  return {
    text: text, // Widgets may truncate text, but we still respect the requested length.
    tooltip,
    class: statusClass,
    alt: metadata.status.toLowerCase(),
    title: metadata.title,
    artist: metadata.artist,
    album: metadata.album,
    player: metadata.player,
    status: metadata.status,
    position: effectivePosition,
    duration: metadata.duration,
    synced: lyrics?.synced === true,
    current,
    upcoming,
    lines: displayLines,
    timedLines,
    currentIndex,
    nextLineTime,
    nextChangeInMs,
    generatedAtMs,
    source: lyrics?.source || "",
  };
}

async function runPlayerControl(
  action: CliOptions["controlAction"],
  player: string,
): Promise<void> {
  switch (action) {
    case "play-pause":
      await $`playerctl --player=${player} play-pause`.quiet();
      break;
    case "play":
      await $`playerctl --player=${player} play`.quiet();
      break;
    case "pause":
      await $`playerctl --player=${player} pause`.quiet();
      break;
    case "next":
      await $`playerctl --player=${player} next`.quiet();
      break;
    case "previous":
      await $`playerctl --player=${player} previous`.quiet();
      break;
    case "stop":
      await $`playerctl --player=${player} stop`.quiet();
      break;
  }
}

async function seekPlayer(position: number, player: string): Promise<void> {
  await $`playerctl --player=${player} position ${position.toFixed(3)}`.quiet();
}

// --- Overlay Control ---
async function controlOverlay(
  action: "show" | "hide" | "toggle",
  options: CliOptions,
): Promise<void> {
  try {
    // Pass options as environment variables to the wrapper
    const env = {
      ...process.env,
      LYRICS_LINES: options.lines.toString(),
      LYRICS_POSITION: options.position,
      LYRICS_FONT_SIZE: options.fontSize.toString(),
      LYRICS_COLOR: options.color,
      LYRICS_OPACITY: options.opacity.toString(),
      LYRICS_SHADOW: options.shadow.toString(),
      LYRICS_SPACING: options.spacing.toString(),
      LYRICS_LENGTH: options.length.toString(),
    };

    await $`toggle-lyrics-overlay ${action}`.env(env).quiet();
  } catch (e) {
    console.error(`Failed to ${action} overlay:`, e);
  }
}

// --- Main Loop ---
async function watchMode(options: CliOptions): Promise<void> {
  let lastTrackKey = "";
  let currentLyrics: LyricsData | null = null;

  while (true) {
    try {
      const metadata = await getMetadata(options.player);

      if (metadata) {
        const trackKey = `${metadata.artist}-${metadata.title}-${metadata.duration}`;

        // Fetch lyrics if track changed
        if (trackKey !== lastTrackKey) {
          lastTrackKey = trackKey;

          // Check cache first
          currentLyrics = await loadLyrics(metadata);
        }
      } else {
        lastTrackKey = "";
        currentLyrics = null;
      }

      if (options.json) {
        const output = formatLyricsWidgetOutput(
          metadata,
          currentLyrics,
          options,
        );
        console.log(JSON.stringify(output));
      } else {
        if (metadata && currentLyrics?.synced) {
          const { current } = getCurrentLines(
            currentLyrics,
            metadata.position,
            1,
          );
          console.log(truncate(current || "♪", options.length));
        } else {
          console.log("");
        }
      }
    } catch (e) {
      if (!options.quiet) {
        console.error("Error:", e);
      }
      if (options.json) {
        console.log(
          JSON.stringify({
            text: "",
            tooltip: "Error",
            class: "error",
            alt: "error",
            title: "",
            artist: "",
            album: "",
            player: "",
            status: "Stopped",
            position: 0,
            duration: 0,
            synced: false,
            current: "",
            upcoming: [],
            lines: [],
            timedLines: [],
            currentIndex: -1,
            nextLineTime: null,
            nextChangeInMs: 1000,
            generatedAtMs: Date.now(),
            source: "",
          }),
        );
      }
    }

    // Update every 500ms for smooth sync
    await Bun.sleep(500);
  }
}

async function currentMode(options: CliOptions): Promise<void> {
  const metadata = await getMetadata(options.player);

  if (!metadata) {
    if (options.json) {
      console.log(JSON.stringify(stoppedOutput("No player")));
    }
    return;
  }

  const lyrics = await loadLyrics(metadata);

  if (options.json) {
    const output = formatLyricsWidgetOutput(metadata, lyrics, options);
    console.log(JSON.stringify(output));
  } else {
    if (lyrics?.synced) {
      const { current, upcoming } = getCurrentLines(
        lyrics,
        metadata.position,
        options.lines,
      );
      console.log(truncate(current, options.length));
      for (const line of upcoming) {
        console.log(truncate(line, options.length));
      }
    } else if (lyrics?.plainText) {
      const lines = lyrics.plainText.split("\n").slice(0, options.lines);
      for (const line of lines) {
        console.log(truncate(line, options.length));
      }
    }
  }
}

async function statusMode(options: CliOptions): Promise<void> {
  const metadata = await getMetadata(options.player);
  const lyrics = metadata ? await loadLyrics(metadata) : null;
  console.log(JSON.stringify(formatLyricsWidgetOutput(metadata, lyrics, options)));
}

async function lookupMode(options: CliOptions): Promise<void> {
  if (!options.lookupTitle || !options.lookupArtist) {
    throw new Error("lookup requires --title and --artist");
  }

  const lyrics = await fetchLyricsFromSources(
    options.lookupTitle,
    options.lookupArtist,
    options.lookupAlbum,
    Math.round(options.lookupDuration),
  );

  console.log(JSON.stringify({
    title: options.lookupTitle,
    artist: options.lookupArtist,
    duration: options.lookupDuration,
    synced: lyrics?.synced === true,
    source: lyrics?.source || "",
    lineCount: lyrics?.lines.length || 0,
    firstLine: lyrics?.lines[0] || null,
    plain: lyrics?.plainText ? true : false,
  }));
}

async function sourcesMode(options: CliOptions): Promise<void> {
  console.log(JSON.stringify(await listPlayerSources(options.player)));
}

function renderTui(output: LyricsWidgetOutput): string {
  const title = output.title || "No player active";
  const artist = output.artist ? ` — ${output.artist}` : "";
  const progress = output.duration > 0 ? ` ${formatProgress(output.position, output.duration)}` : "";
  const state = output.status === "Playing" ? "▶" : output.status === "Paused" ? "⏸" : "■";
  const lyrics = output.lines.length > 0 ? output.lines : [output.text || "♪"];
  return [
    "\x1b[2J\x1b[H\x1b[1mlyricsctl\x1b[0m",
    `${state} ${title}${artist}${progress}`,
    "",
    ...lyrics.map((line, index) => (index === 0 ? `\x1b[1m${line}\x1b[0m` : `  ${line}`)),
    "",
    "space play/pause · n next · p previous · o overlay · h hide · q quit",
  ].join("\n");
}

async function tuiMode(options: CliOptions): Promise<void> {
  if (!process.stdin.isTTY || !process.stdout.isTTY) {
    await statusMode({ ...options, json: true });
    return;
  }

  let quit = false;
  let lastTrackKey = "";
  let currentLyrics: LyricsData | null = null;

  const cleanup = () => {
    process.stdin.setRawMode(false);
    process.stdin.pause();
    process.stdout.write("\x1b[?25h\x1b[0m\n");
  };

  process.stdin.setRawMode(true);
  process.stdin.resume();
  process.stdout.write("\x1b[?25l");

  process.stdin.on("data", (chunk) => {
    const key = chunk.toString("utf8");
    if (key === "q" || key === "\u0003") {
      quit = true;
      return;
    }
    if (key === " ") void runPlayerControl("play-pause", options.player).catch(() => { });
    else if (key === "n") void runPlayerControl("next", options.player).catch(() => { });
    else if (key === "p") void runPlayerControl("previous", options.player).catch(() => { });
    else if (key === "o") void controlOverlay("toggle", options).catch(() => { });
    else if (key === "h") void controlOverlay("hide", options).catch(() => { });
  });

  try {
    while (!quit) {
      const metadata = await getMetadata(options.player);
      if (metadata) {
        const trackKey = `${metadata.artist}-${metadata.title}-${metadata.duration}`;
        if (trackKey !== lastTrackKey) {
          lastTrackKey = trackKey;
          currentLyrics = await loadLyrics(metadata);
        }
      } else {
        lastTrackKey = "";
        currentLyrics = null;
      }
      process.stdout.write(renderTui(formatLyricsWidgetOutput(metadata, currentLyrics, options)));
      await Bun.sleep(500);
    }
  } finally {
    cleanup();
  }
}

// --- Entry Point ---
async function main() {
  const options = parseArgs();
  await mkdir(CACHE_DIR, { recursive: true });

  switch (options.command) {
    case "watch":
      await watchMode(options);
      break;
    case "current":
      await currentMode(options);
      break;
    case "status":
      await statusMode(options);
      break;
    case "lookup":
      await lookupMode(options);
      break;
    case "sources":
      await sourcesMode(options);
      break;
    case "control":
      await runPlayerControl(options.controlAction, options.player);
      break;
    case "seek":
      await seekPlayer(options.seekPosition, options.player);
      break;
    case "tui":
      await tuiMode(options);
      break;
    case "show":
      await controlOverlay("show", options);
      break;
    case "hide":
      await controlOverlay("hide", options);
      break;
    case "toggle":
      await controlOverlay("toggle", options);
      break;
  }
}

main().catch((e) => {
  console.error("Fatal error:", e);
  process.exit(1);
});
