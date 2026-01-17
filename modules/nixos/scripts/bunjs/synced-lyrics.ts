#!/usr/bin/env bun
// synced-lyrics.ts - Synced lyrics fetcher and display for waybar/quickshell
import { $ } from "bun";
import { mkdir } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";

// --- Configuration ---
const CACHE_DIR = join(tmpdir(), "synced-lyrics-cache");
const DEFAULT_PLAYER = "mpd,%any";
const LRCLIB_API = "https://lrclib.net/api";
const USER_AGENT = "synced-lyrics/1.0 (https://github.com/user/nixconf)";

// --- Types ---
interface TrackMetadata {
  title: string;
  artist: string;
  album: string;
  duration: number; // in seconds
  position: number; // in seconds
  status: "Playing" | "Paused" | "Stopped";
  player: string;
}

interface LyricLine {
  time: number; // in seconds
  text: string;
}

interface LyricsData {
  synced: boolean;
  lines: LyricLine[];
  plainText?: string;
}

interface WaybarOutput {
  text: string;
  tooltip: string;
  class: string;
  alt: string;
}

// --- CLI Parsing ---
interface CliOptions {
  command: "watch" | "current" | "show" | "hide" | "toggle";
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

    // Commands (first positional arg)
    if (!arg?.startsWith("-")) {
      if (["watch", "current", "show", "hide", "toggle"].includes(arg!)) {
        options.command = arg as CliOptions["command"];
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
        options.lines = parseInt(args[i] || "3") || 3;
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
      case "--quiet":
      case "-q":
        options.quiet = true;
        break;
      case "--help":
      case "-h":
        console.log(`
synced-lyrics - Display synced lyrics for currently playing music

Commands:
  watch           Continuous output for waybar (default)
  current         Print current lyric line once
  show            Show lyrics overlay
  hide            Hide lyrics overlay  
  toggle          Toggle lyrics overlay

Options:
  --json, -j      Output JSON for waybar
  --progress, -p  Show progress/timestamp
  --lines N, -l N Number of lines to display (default: 3)
  --length N      Max line length before truncation (default: 0, disabled)
  --player NAME   Player to use (default: mpd,%any)
  --quiet, -q     Suppress errors
  
Overlay Options:
  --font-size N   Font size for overlay (default: 28)
  --color HEX     Text color (default: #ffffff)
  --position POS  Overlay position: top, bottom, center (default: bottom)
  --opacity N     Text opacity (0.0-1.0, default: 0.95)
  --shadow BOOL   Show text shadow/outline (default: true)
  --spacing N     Spacing between lines (default: 8)
  --help, -h      Show this help
`);
        process.exit(0);
    }
    i++;
  }

  return options;
}

// --- Playerctl Integration ---
async function getMetadata(player: string): Promise<TrackMetadata | null> {
  try {
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
      duration: Math.round(lengthUs / 1_000_000),
      position: Math.round(positionSec),
      status: (status.trim() as TrackMetadata["status"]) || "Stopped",
      player: playerName.trim(),
    };
  } catch {
    return null;
  }
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
      // Clean up
      .replace(/\s+/g, " ")
      .trim()
  );
}

function normalizeArtist(artist: string): string {
  // Take first artist if multiple
  return artist.split(/[,&]/)[0]!.replace(/\s+/g, " ").trim();
}

// --- LRCLIB API ---
async function fetchFromLrclib(
  title: string,
  artist: string,
  album: string,
  duration: number
): Promise<LyricsData | null> {
  const headers = { "User-Agent": USER_AGENT };

  // Try exact match first
  try {
    const params = new URLSearchParams({
      track_name: title,
      artist_name: artist,
      duration: duration.toString(),
    });
    if (album) params.set("album_name", album);

    const response = await fetch(`${LRCLIB_API}/get?${params}`, { headers });

    if (response.ok) {
      const data = (await response.json()) as any;
      if (data.syncedLyrics) {
        return {
          synced: true,
          lines: parseLrc(data.syncedLyrics),
        };
      }
      if (data.plainLyrics) {
        return {
          synced: false,
          lines: [],
          plainText: data.plainLyrics,
        };
      }
    }
  } catch {}

  // Try normalized title
  const normTitle = normalizeTitle(title);
  const normArtist = normalizeArtist(artist);

  if (normTitle !== title || normArtist !== artist) {
    try {
      const params = new URLSearchParams({
        track_name: normTitle,
        artist_name: normArtist,
        duration: duration.toString(),
      });

      const response = await fetch(`${LRCLIB_API}/get?${params}`, { headers });

      if (response.ok) {
        const data = (await response.json()) as any;
        if (data.syncedLyrics) {
          return {
            synced: true,
            lines: parseLrc(data.syncedLyrics),
          };
        }
        if (data.plainLyrics) {
          return {
            synced: false,
            lines: [],
            plainText: data.plainLyrics,
          };
        }
      }
    } catch {}
  }

  // Try search as fallback
  try {
    const query = `${normArtist} ${normTitle}`;
    const response = await fetch(
      `${LRCLIB_API}/search?q=${encodeURIComponent(query)}`,
      { headers }
    );

    if (response.ok) {
      const results = (await response.json()) as any[];

      // Find best match by duration (within 5 seconds)
      const match =
        results.find((r) => Math.abs(r.duration - duration) <= 5) || results[0];

      if (match?.syncedLyrics) {
        return {
          synced: true,
          lines: parseLrc(match.syncedLyrics),
        };
      }
      if (match?.plainLyrics) {
        return {
          synced: false,
          lines: [],
          plainText: match.plainLyrics,
        };
      }
    }
  } catch {}

  return null;
}

// --- LRC Parsing ---
function parseLrc(lrcText: string): LyricLine[] {
  const lines: LyricLine[] = [];
  const lineRegex = /\[(\d{2}):(\d{2})\.(\d{2,3})\]\s*(.*)/;

  for (const line of lrcText.split("\n")) {
    const match = line.match(lineRegex);
    if (match) {
      const minutes = parseInt(match[1]!);
      const seconds = parseInt(match[2]!);
      const ms = parseInt(match[3]!.padEnd(3, "0"));
      const text = match[4]!.trim();

      if (text) {
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
  numLines: number
): { current: string; upcoming: string[]; index: number } {
  if (!lyrics.synced || lyrics.lines.length === 0) {
    return { current: "", upcoming: [], index: -1 };
  }

  // Binary search for current line
  let left = 0;
  let right = lyrics.lines.length - 1;
  let currentIndex = 0;

  while (left <= right) {
    const mid = Math.floor((left + right) / 2);
    if (lyrics.lines[mid]!.time <= position) {
      currentIndex = mid;
      left = mid + 1;
    } else {
      right = mid - 1;
    }
  }

  const current = lyrics.lines[currentIndex]?.text || "";
  const upcoming: string[] = [];

  for (let i = 1; i < numLines && currentIndex + i < lyrics.lines.length; i++) {
    upcoming.push(lyrics.lines[currentIndex + i]!.text);
  }

  return { current, upcoming, index: currentIndex };
}

// --- Caching ---
function getCacheKey(metadata: TrackMetadata): string {
  const clean = (s: string) => s.replace(/[^a-zA-Z0-9]/g, "_").toLowerCase();
  return `${clean(metadata.artist)}-${clean(metadata.title)}-${
    metadata.duration
  }.lrc`;
}

async function getCachedLyrics(
  metadata: TrackMetadata
): Promise<LyricsData | null> {
  try {
    const cacheFile = join(CACHE_DIR, getCacheKey(metadata));
    const file = Bun.file(cacheFile);
    if (await file.exists()) {
      const content = await file.text();
      const data = JSON.parse(content);
      return data as LyricsData;
    }
  } catch {}
  return null;
}

async function cacheLyrics(
  metadata: TrackMetadata,
  lyrics: LyricsData
): Promise<void> {
  try {
    await mkdir(CACHE_DIR, { recursive: true });
    const cacheFile = join(CACHE_DIR, getCacheKey(metadata));
    await Bun.write(cacheFile, JSON.stringify(lyrics));
  } catch {}
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

function formatWaybarOutput(
  metadata: TrackMetadata | null,
  lyrics: LyricsData | null,
  options: CliOptions
): WaybarOutput {
  if (!metadata) {
    return {
      text: "",
      tooltip: "No player active",
      class: "stopped",
      alt: "stopped",
    };
  }

  const { current, upcoming } = lyrics?.synced
    ? getCurrentLines(lyrics, metadata.position, options.lines)
    : { current: "", upcoming: [] };

  let text = truncate(current || "♪", options.length);
  if (options.progress && metadata.duration > 0) {
    text = `${formatProgress(metadata.position, metadata.duration)} ${text}`;
  }

  // Build tooltip with context
  let tooltip = `<b>${truncate(metadata.title, options.length)}</b>\n${truncate(
    metadata.artist,
    options.length
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
    text: text, // Waybar already handles truncation if configured, but we respect our length opt
    tooltip,
    class: statusClass,
    alt: metadata.status.toLowerCase(),
  };
}

// --- Overlay Control ---
async function controlOverlay(
  action: "show" | "hide" | "toggle",
  options: CliOptions
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
          currentLyrics = await getCachedLyrics(metadata);

          if (!currentLyrics) {
            currentLyrics = await fetchFromLrclib(
              metadata.title,
              metadata.artist,
              metadata.album,
              metadata.duration
            );

            if (currentLyrics) {
              await cacheLyrics(metadata, currentLyrics);
            }
          }
        }
      } else {
        lastTrackKey = "";
        currentLyrics = null;
      }

      if (options.json) {
        const output = formatWaybarOutput(metadata, currentLyrics, options);
        console.log(JSON.stringify(output));
      } else {
        if (metadata && currentLyrics?.synced) {
          const { current } = getCurrentLines(
            currentLyrics,
            metadata.position,
            1
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
          })
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
      console.log(
        JSON.stringify({
          text: "",
          tooltip: "No player",
          class: "stopped",
          alt: "stopped",
        })
      );
    }
    return;
  }

  let lyrics = await getCachedLyrics(metadata);

  if (!lyrics) {
    lyrics = await fetchFromLrclib(
      metadata.title,
      metadata.artist,
      metadata.album,
      metadata.duration
    );

    if (lyrics) {
      await cacheLyrics(metadata, lyrics);
    }
  }

  if (options.json) {
    const output = formatWaybarOutput(metadata, lyrics, options);
    console.log(JSON.stringify(output));
  } else {
    if (lyrics?.synced) {
      const { current, upcoming } = getCurrentLines(
        lyrics,
        metadata.position,
        options.lines
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
