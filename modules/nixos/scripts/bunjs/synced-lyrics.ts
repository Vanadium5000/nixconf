#!/usr/bin/env bun
// lyricsctl - synced lyrics fetcher, shell widget JSON source, and terminal UI
import { $ } from "bun";
import { mkdir } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";

// --- Configuration ---
const CACHE_DIR = join(tmpdir(), "synced-lyrics-cache");
const DEFAULT_PLAYER = "mpd,%any";
const LRCLIB_API = "https://lrclib.net/api";
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
}

// --- CLI Parsing ---
interface CliOptions {
  command: "watch" | "current" | "status" | "show" | "hide" | "toggle" | "control" | "tui";
  controlAction: "play-pause" | "play" | "pause" | "next" | "previous" | "stop";
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
      if (["watch", "current", "status", "show", "hide", "toggle", "control", "tui"].includes(arg!)) {
        options.command = arg as CliOptions["command"];
      } else if (options.command === "control" && ["play-pause", "play", "pause", "next", "previous", "stop"].includes(arg!)) {
        options.controlAction = arg as CliOptions["controlAction"];
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
  control ACTION  Run player control: play-pause, play, pause, next, previous, stop
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
  };
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

// --- LRCLIB API ---
async function fetchFromLrclib(
  title: string,
  artist: string,
  album: string,
  duration: number,
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

  // Try parsing "Artist - Title" from title (common in some files)
  if (title.includes(" - ")) {
    const parts = title.split(" - ");
    if (parts.length >= 2) {
      const extractedArtist = parts[0]!.trim();
      const extractedTitle = parts.slice(1).join(" - ").trim();
      const normExtTitle = normalizeTitle(extractedTitle);

      try {
        const params = new URLSearchParams({
          track_name: normExtTitle,
          artist_name: extractedArtist,
          duration: duration.toString(),
        });

        const response = await fetch(`${LRCLIB_API}/get?${params}`, {
          headers,
        });

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
  numLines: number,
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
  metadata: TrackMetadata,
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
  lyrics: LyricsData,
): Promise<void> {
  try {
    await mkdir(CACHE_DIR, { recursive: true });
    const cacheFile = join(CACHE_DIR, getCacheKey(metadata));
    await Bun.write(cacheFile, JSON.stringify(lyrics));
  } catch {}
}

async function loadLyrics(metadata: TrackMetadata): Promise<LyricsData | null> {
  const cached = await getCachedLyrics(metadata);
  if (cached) return cached;

  const fetched = await fetchFromLrclib(
    metadata.title,
    metadata.artist,
    metadata.album,
    metadata.duration,
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

  const { current, upcoming } = lyrics?.synced
    ? getCurrentLines(lyrics, metadata.position, options.lines)
    : { current: "", upcoming: [] };
  const plainLines = lyrics?.plainText
    ? lyrics.plainText
        .split("\n")
        .map((line) => truncate(line.trim(), options.length))
        .filter(Boolean)
        .slice(0, options.lines)
    : [];
  const displayLines = lyrics?.synced
    ? [current || "♪", ...upcoming].map((line) => truncate(line, options.length))
    : plainLines;

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
    position: metadata.position,
    duration: metadata.duration,
    synced: lyrics?.synced === true,
    current,
    upcoming,
    lines: displayLines,
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
    if (key === " ") void runPlayerControl("play-pause", options.player).catch(() => {});
    else if (key === "n") void runPlayerControl("next", options.player).catch(() => {});
    else if (key === "p") void runPlayerControl("previous", options.player).catch(() => {});
    else if (key === "o") void controlOverlay("toggle", options).catch(() => {});
    else if (key === "h") void controlOverlay("hide", options).catch(() => {});
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
    case "control":
      await runPlayerControl(options.controlAction, options.player);
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
