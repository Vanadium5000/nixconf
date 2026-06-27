#!/usr/bin/env bun
// lyricsctl - synced lyrics fetcher, shell widget JSON source, and terminal UI
import { $ } from "bun";
import { mkdir, unlink } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";

// --- Configuration ---
const CACHE_DIR = join(tmpdir(), "synced-lyrics-cache");
const CACHE_VERSION = 4;
const DEFAULT_PLAYER = "mpd,%any";
const LRCLIB_API = "https://lrclib.net/api";
const LRCCX_API = "https://api.lrc.cx/lyrics";
const USER_AGENT = "lyricsctl/1.0";
const MAX_LEADING_OFFSET_SECONDS = 30;
const MIN_LEADING_OFFSET_SECONDS = 4;
const LRCLIB_DURATION_TOLERANCE_SECONDS = 2;

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
  sourceId?: string;
  sourceDuration?: number;
  sourceAlbum?: string;
  timingOffset?: number;
  timingOffsetReason?: string;
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
  allTimedLines: TimedLyricLine[];
  currentIndex: number;
  nextLineTime: number | null;
  nextChangeInMs: number;
  generatedAtMs: number;
  source: string;
  sourceId: string;
  sourceDuration: number;
  sourceAlbum: string;
  timingOffset: number;
  timingOffsetReason: string;
  diagnostics: string;
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
  lookupPosition: number;
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
    lookupPosition: 0,
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
        options.lookupDuration = parseFloat(args[i] || "0") || 0;
        break;
      case "--lookup-position":
      case "--test-position":
        i++;
        options.lookupPosition = Math.max(0, parseFloat(args[i] || "0") || 0);
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
  --test-position N  Print lookup current line at this song position
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
    allTimedLines: [],
    currentIndex: -1,
    nextLineTime: null,
    nextChangeInMs: 1000,
    generatedAtMs: Date.now(),
    source: "",
    sourceId: "",
    sourceDuration: 0,
    sourceAlbum: "",
    timingOffset: 0,
    timingOffsetReason: "",
    diagnostics: tooltip,
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
      // Normalize punctuation that sources commonly disagree about.
      .replace(/[?'’]+$/g, "")
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

function withLrclibMetadata(lyrics: LyricsData, result: any, source: string, duration: number): LyricsData {
  const sourceDuration = Number.isFinite(Number(result?.duration)) ? Number(result.duration) : 0;
  const firstTime = lyrics.lines[0]?.time ?? 0;
  const durationDelta = sourceDuration > 0 && duration > 0 ? duration - sourceDuration : 0;
  // LRCLIB's signature API treats ±2s as the same track, so leave that slack unshifted when reconciling video-duration MPRIS tracks with audio-duration lyric records. Ref: https://lrclib.net/docs
  const leadingOffset = durationDelta > 0 ? Math.max(0, durationDelta - LRCLIB_DURATION_TOLERANCE_SECONDS) : durationDelta;
  const shouldOffsetForLongerTrack = lyrics.synced
    && firstTime <= 8
    && leadingOffset >= MIN_LEADING_OFFSET_SECONDS
    && leadingOffset <= MAX_LEADING_OFFSET_SECONDS;
  const base = {
    ...lyrics,
    source,
    sourceId: result?.id !== undefined ? String(result.id) : "",
    sourceDuration,
    sourceAlbum: String(result?.albumName || ""),
    timingOffset: 0,
    timingOffsetReason: timingDiagnosticReason(lyrics, duration, sourceDuration),
    cacheVersion: CACHE_VERSION,
  };

  if (!shouldOffsetForLongerTrack) return base;
  return applyTimingOffset(
    base,
    leadingOffset,
    `shifted by source/track duration delta minus tolerance (+${leadingOffset.toFixed(2)}s); ${base.timingOffsetReason || ""}`.trim(),
  );
}

function withLrcCxMetadata(lyrics: LyricsData, duration: number): LyricsData {
  return {
    ...lyrics,
    source: "lrc.cx",
    sourceId: "",
    sourceDuration: 0,
    sourceAlbum: "",
    timingOffset: 0,
    timingOffsetReason: timingDiagnosticReason(lyrics, duration, 0),
    cacheVersion: CACHE_VERSION,
  };
}

function normalizedKey(value: string): string {
  return normalizeTitle(value).toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
}

function normalizedLineText(value: string): string {
  return value.toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
}

function lyricSignature(lyrics: LyricsData | null): string {
  if (!lyrics?.synced) return "";
  return lyrics.lines.map((line) => normalizedLineText(line.text)).filter(Boolean).join("\n");
}

function titleCandidates(title: string, artist: string): string[] {
  const candidates = [title, normalizeTitle(title)];
  const separator = " - ";
  const separatorIndex = title.indexOf(separator);

  if (separatorIndex > 0) {
    const prefix = title.slice(0, separatorIndex).trim();
    const suffix = title.slice(separatorIndex + separator.length).trim();
    if (normalizedKey(prefix) === normalizedKey(artist) && suffix) {
      candidates.push(suffix, normalizeTitle(suffix));
    }
  }

  return [...new Set(candidates.map(normalizedKey).filter(Boolean))];
}

function lastLyricTime(lyrics: LyricsData): number {
  return lyrics.lines[lyrics.lines.length - 1]?.time ?? 0;
}

function lyricSpan(lyrics: LyricsData): number {
  if (!lyrics.synced || lyrics.lines.length < 2) return 0;
  return Math.max(0, lastLyricTime(lyrics) - lyrics.lines[0]!.time);
}

function timingDiagnosticReason(lyrics: LyricsData | null, trackDuration: number, sourceDuration: number): string {
  if (!lyrics?.synced || lyrics.lines.length === 0) return "";
  const parts: string[] = [];
  const firstTime = lyrics.lines[0]!.time;
  const lastTime = lastLyricTime(lyrics);

  if (sourceDuration > 0 && trackDuration > 0) {
    parts.push(`source ${sourceDuration.toFixed(1)}s vs track ${trackDuration.toFixed(1)}s`);
  } else if (trackDuration > 0) {
    parts.push(`track ${trackDuration.toFixed(1)}s`);
  }

  parts.push(`lyrics ${firstTime.toFixed(2)}s-${lastTime.toFixed(2)}s`);
  if (sourceDuration > 0 && trackDuration > 0 && Math.abs(sourceDuration - trackDuration) > 2) {
    parts.push(`duration delta ${(sourceDuration - trackDuration).toFixed(1)}s`);
  }
  return parts.join(" · ");
}

function firstMatchedLineDelta(candidate: LyricsData, reference: LyricsData): number | null {
  if (!candidate.synced || !reference.synced) return null;
  const referenceTimes = new Map<string, number>();

  for (const line of reference.lines) {
    const key = normalizedLineText(line.text);
    if (key && !referenceTimes.has(key)) referenceTimes.set(key, line.time);
  }

  for (const line of candidate.lines) {
    const key = normalizedLineText(line.text);
    const referenceTime = key ? referenceTimes.get(key) : undefined;
    if (referenceTime !== undefined) return referenceTime - line.time;
  }

  return null;
}

function lineTimingShapePenalty(candidate: LyricsData, reference: LyricsData | null): number {
  if (!candidate.synced || !reference?.synced) return 0;
  const referenceTimes = new Map<string, number>();
  const deltas: number[] = [];

  for (const line of reference.lines) {
    const key = normalizedLineText(line.text);
    if (key && !referenceTimes.has(key)) referenceTimes.set(key, line.time);
  }

  for (const line of candidate.lines) {
    const key = normalizedLineText(line.text);
    const referenceTime = key ? referenceTimes.get(key) : undefined;
    if (referenceTime !== undefined) deltas.push(referenceTime - line.time);
    if (deltas.length >= 16) break;
  }

  if (deltas.length < 4) return 0;
  const first = deltas[0]!;
  const maxDrift = Math.max(...deltas.map((delta) => Math.abs(delta - first)));
  return Math.min(160, maxDrift * 8);
}

function applyTimingOffset(lyrics: LyricsData, offset: number, reason: string): LyricsData {
  if (!lyrics.synced || Math.abs(offset) < 0.01) return lyrics;
  return {
    ...lyrics,
    lines: lyrics.lines.map((line) => ({ ...line, time: Math.max(0, line.time + offset) })),
    timingOffset: Number(offset.toFixed(3)),
    timingOffsetReason: reason,
  };
}

function hasSuspiciousEarlyEnd(lyrics: LyricsData, duration: number): boolean {
  if (!lyrics.synced || lyrics.lines.length === 0 || duration < 90) return false;

  const lastTime = lastLyricTime(lyrics);
  const trailingSilence = duration - lastTime;

  // Some songs have long instrumental outros, so only reject lyrics that are
  // both far from the track end and proportionally much shorter than the track.
  return trailingSilence > 45 && lastTime / duration < 0.65;
}

function syncedTimingPenalty(lyrics: LyricsData | null, duration: number): number {
  if (!lyrics?.synced || lyrics.lines.length === 0 || duration <= 0) return 0;
  if (hasSuspiciousEarlyEnd(lyrics, duration)) return 1_000;

  const distanceFromEnd = Math.abs(duration - lastLyricTime(lyrics));
  const leadingOffset = lyrics.lines[0]?.time ?? 0;
  const spanDistance = Math.abs(duration - lyricSpan(lyrics));
  return Math.min(80, distanceFromEnd / 2) + Math.min(40, spanDistance / 4) + Math.min(20, leadingOffset / 2);
}

function scoreLrclibResult(result: any, title: string, artist: string, duration: number): number {
  const resultTitle = normalizedKey(result.trackName || result.name || "");
  const possibleTitles = titleCandidates(title, artist);
  const titleScore = possibleTitles.includes(resultTitle)
    ? 0
    : possibleTitles.some((candidate) => resultTitle.includes(candidate) || candidate.includes(resultTitle))
      ? 10
      : 40;
  const artistScore = normalizedKey(result.artistName || "") === normalizedKey(artist) ? 0 : 20;
  const durationScore = Number.isFinite(Number(result.duration)) ? Math.min(60, Math.abs(Number(result.duration) - duration) * 1.2) : 30;
  const synced = lyricTextToSyncedData(result?.syncedLyrics);
  return titleScore + artistScore + durationScore + syncedTimingPenalty(synced, duration);
}

function scoreAnySyncedLyrics(lyrics: LyricsData, sourceDuration: number, duration: number, reference: LyricsData | null = null): number {
  const sourceDelta = sourceDuration > 0 && duration > 0 ? Math.abs(sourceDuration - duration) : 12;
  const firstTime = lyrics.lines[0]?.time ?? 0;
  const spanDelta = duration > 0 ? Math.abs(duration - lyricSpan(lyrics)) : 0;
  const offsetPenalty = lyrics.timingOffset ? Math.max(0, 14 - Math.abs(lyrics.timingOffset)) * 8 : 0;
  return sourceDelta * 1.2 + Math.min(30, firstTime) + Math.min(60, spanDelta / 4) + syncedTimingPenalty(lyrics, duration) + lineTimingShapePenalty(lyrics, reference) + offsetPenalty;
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
  const syncedCandidates: LyricsData[] = [];

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
      if (synced && !hasSuspiciousEarlyEnd(synced, duration)) return withLrclibMetadata(synced, data, "lrclib/get", duration);
      const plain = lyricTextToPlainData(data.plainLyrics);
      if (plain && !bestPlain) bestPlain = withLrclibMetadata(plain, data, "lrclib/get", duration);
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
        .filter((r) => {
          const resultTitle = normalizedKey(r.trackName || r.name || "");
          return titleCandidates(title, artist).some((candidate) => resultTitle.includes(candidate) || candidate.includes(resultTitle));
        })
        .sort((a, b) => scoreLrclibResult(a, title, artist, duration) - scoreLrclibResult(b, title, artist, duration));

      for (const match of sorted.length > 0 ? sorted : results) {
        const synced = lyricTextToSyncedData(match?.syncedLyrics);
        if (synced && !hasSuspiciousEarlyEnd(synced, duration)) syncedCandidates.push(withLrclibMetadata(synced, match, "lrclib/search", duration));
        const plain = lyricTextToPlainData(match?.plainLyrics);
        if (plain && !bestPlain) bestPlain = withLrclibMetadata(plain, match, "lrclib/search", duration);
      }
    }
  } catch { }

  if (syncedCandidates.length > 0) {
    syncedCandidates.sort((a, b) =>
      scoreAnySyncedLyrics(a, a.sourceDuration || 0, duration) - scoreAnySyncedLyrics(b, b.sourceDuration || 0, duration),
    );
    return syncedCandidates[0]!;
  }

  return bestPlain;
}

async function fetchLrclibSyncedCandidates(title: string, artist: string, duration: number): Promise<LyricsData[]> {
  const headers = { "User-Agent": USER_AGENT };
  const normTitle = [...titleCandidates(title, artist)].sort((a, b) => a.length - b.length)[0] || normalizeTitle(title);
  const normArtist = normalizeArtist(artist);
  const params = new URLSearchParams({ track_name: normTitle, artist_name: normArtist });

  try {
    const response = await fetch(`${LRCLIB_API}/search?${params}`, { headers });
    if (!response.ok) return [];
    const seen = new Set<string>();
    const results = (await response.json()) as any[];
    return results
      .filter((result) => {
        const resultTitle = normalizedKey(result.trackName || result.name || "");
        return titleCandidates(title, artist).some((candidate) => resultTitle.includes(candidate) || candidate.includes(resultTitle));
      })
      .map((result) => {
        const synced = lyricTextToSyncedData(result?.syncedLyrics);
        return synced ? withLrclibMetadata(synced, result, "lrclib/search", duration) : null;
      })
      .filter((lyrics): lyrics is LyricsData => {
        if (!lyrics || (!lyrics.timingOffset && hasSuspiciousEarlyEnd(lyrics, duration))) return false;
        const key = lyrics.sourceId || `${lyrics.sourceDuration}:${lyricSignature(lyrics).slice(0, 64)}`;
        if (seen.has(key)) return false;
        seen.add(key);
        return true;
      });
  } catch { }

  return [];
}

async function fetchFromLrcCx(title: string, artist: string, duration: number): Promise<LyricsData | null> {
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
      if (synced && !hasSuspiciousEarlyEnd(synced, duration)) return withLrcCxMetadata(synced, duration);
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
  const lrcCx = await fetchFromLrcCx(title, artist, duration);
  const lrclibCandidates = lrcCx?.synced ? await fetchLrclibSyncedCandidates(title, artist, duration) : [];
  const shiftedLrclibCandidate = lrclibCandidates
    .filter((candidate) => candidate.timingOffset && Math.abs(candidate.timingOffset) >= MIN_LEADING_OFFSET_SECONDS)
    .sort((a, b) => Math.abs((a.sourceDuration || duration) - duration) - Math.abs((b.sourceDuration || duration) - duration))[0] || null;
  if (shiftedLrclibCandidate) return shiftedLrclibCandidate;

  const lrclibBest = lrclibCandidates.length > 0
    ? lrclibCandidates.sort((a, b) => scoreAnySyncedLyrics(a, a.sourceDuration || 0, duration, lrcCx) - scoreAnySyncedLyrics(b, b.sourceDuration || 0, duration, lrcCx))[0]!
    : lrclib;

  if (lrclibBest?.synced && lrcCx?.synced) {
    const lrclibFirst = lrclibBest.lines[0]?.time ?? 0;
    const lrcCxFirst = lrcCx.lines[0]?.time ?? 0;
    const deltaToLrcCx = firstMatchedLineDelta(lrclibBest, lrcCx);
    const lrclibDurationDelta = lrclibBest.sourceDuration && duration > 0 ? Math.abs(lrclibBest.sourceDuration - duration) : Number.POSITIVE_INFINITY;
    const lrclibLooksEarly = deltaToLrcCx !== null
      && deltaToLrcCx >= MIN_LEADING_OFFSET_SECONDS
      && deltaToLrcCx <= MAX_LEADING_OFFSET_SECONDS
      && lrclibFirst + MIN_LEADING_OFFSET_SECONDS < lrcCxFirst
      && lrclibDurationDelta > 2;

    if (lrclibLooksEarly) {
      return applyTimingOffset(
        lrclibBest,
        deltaToLrcCx,
        `aligned to lrc.cx first shared line (+${deltaToLrcCx.toFixed(2)}s); ${lrclibBest.timingOffsetReason || ""}`.trim(),
      );
    }

    if (lrclibBest.timingOffset && Math.abs(lrclibBest.timingOffset) >= MIN_LEADING_OFFSET_SECONDS) {
      return lrclibBest;
    }

    return scoreAnySyncedLyrics(lrclibBest, lrclibBest.sourceDuration || 0, duration, lrcCx) <= scoreAnySyncedLyrics(lrcCx, lrcCx.sourceDuration || 0, duration)
      ? lrclibBest
      : lrcCx;
  }

  if (lrclibBest?.synced) return lrclibBest;
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
  const { start, end } = getLyricWindowBounds(lyrics.lines.length, currentIndex, numLines);
  const previous: string[] = [];
  const upcoming: string[] = [];

  for (let i = start; i < end; i++) {
    if (i < currentIndex) previous.push(lyrics.lines[i]!.text);
    else if (i > currentIndex || currentIndex < 0) upcoming.push(lyrics.lines[i]!.text);
  }

  return { current, upcoming, previous, index: currentIndex };
}

function getLyricWindowBounds(
  lineCount: number,
  currentIndex: number,
  windowSize: number,
): { start: number; end: number } {
  const size = Math.max(1, Math.min(windowSize, lineCount));
  if (lineCount <= size) return { start: 0, end: lineCount };
  if (currentIndex < 0) return { start: 0, end: size };

  const preferredBefore = Math.min(5, Math.floor((size - 1) / 2));
  let start = currentIndex - preferredBefore;
  let end = start + size;

  if (start < 0) {
    start = 0;
    end = size;
  } else if (end > lineCount) {
    end = lineCount;
    start = lineCount - size;
  }

  return { start, end };
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
      if (lyrics.cacheVersion !== CACHE_VERSION || !lyrics.synced) {
        await unlink(cacheFile).catch(() => { });
        return null;
      }
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

function formatLyricsDiagnostics(lyrics: LyricsData | null, metadata: TrackMetadata | null): string {
  if (!lyrics) return "No lyrics source";
  const parts = [lyrics.source || "unknown"];
  if (lyrics.sourceId) parts.push(`#${lyrics.sourceId}`);
  if (lyrics.sourceAlbum) parts.push(lyrics.sourceAlbum);
  if (lyrics.sourceDuration && lyrics.sourceDuration > 0) parts.push(`source ${lyrics.sourceDuration.toFixed(1)}s`);
  if (metadata?.duration && metadata.duration > 0) parts.push(`track ${metadata.duration.toFixed(1)}s`);
  if (lyrics.synced && lyrics.lines.length > 0) {
    parts.push(`lyrics ${lyrics.lines[0]!.time.toFixed(2)}s-${lastLyricTime(lyrics).toFixed(2)}s`);
  }
  if (lyrics.timingOffset && Math.abs(lyrics.timingOffset) >= 0.01) parts.push(`offset ${lyrics.timingOffset.toFixed(2)}s`);
  if (lyrics.timingOffsetReason) parts.push(lyrics.timingOffsetReason);
  return parts.filter(Boolean).join(" · ");
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
    ? (currentIndex >= 0 ? [...previous, current || "♪", ...upcoming] : upcoming).map((line) => truncate(line, options.length))
    : plainLines;
  const windowBounds = lyrics?.synced
    ? getLyricWindowBounds(lyrics.lines.length, currentIndex, options.lines)
    : { start: 0, end: 0 };
  const timedLines = lyrics?.synced
    ? lyrics.lines
      .slice(windowBounds.start, windowBounds.end)
      .map((line) => ({
        time: line.time,
        text: truncate(line.text, options.length),
        current: currentIndex >= 0 && line.time === lyrics.lines[currentIndex]?.time,
      }))
    : [];
  const allTimedLines = lyrics?.synced
    ? lyrics.lines.map((line, index) => ({
      time: line.time,
      text: truncate(line.text, options.length),
      current: index === currentIndex,
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
  const diagnostics = formatLyricsDiagnostics(lyrics, metadata);

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
    allTimedLines,
    currentIndex,
    nextLineTime,
    nextChangeInMs,
    generatedAtMs,
    source: lyrics?.source || "",
    sourceId: lyrics?.sourceId || "",
    sourceDuration: lyrics?.sourceDuration || 0,
    sourceAlbum: lyrics?.sourceAlbum || "",
    timingOffset: lyrics?.timingOffset || 0,
    timingOffsetReason: lyrics?.timingOffsetReason || "",
    diagnostics,
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
    // Let toggle-lyrics-overlay own visual defaults, matching the Hyprland
    // Super+Alt+M binding. Only override the data command when the user chose a
    // non-default player source in the DMS widget.
    const env = { ...process.env };
    if (options.player !== DEFAULT_PLAYER) {
      env.OVERLAY_COMMAND = [
        Bun.argv[0] || "lyricsctl",
        import.meta.path,
        "current",
        "--json",
        "--player",
        options.player,
        "--lines",
        "4",
        "--length",
        options.length.toString(),
      ].join(" ");
    }

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
            allTimedLines: [],
            currentIndex: -1,
            nextLineTime: null,
            nextChangeInMs: 1000,
            generatedAtMs: Date.now(),
            source: "",
            sourceId: "",
            sourceDuration: 0,
            sourceAlbum: "",
            timingOffset: 0,
            timingOffsetReason: "",
            diagnostics: "Error",
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
  const lookupCurrent = lyrics?.synced && options.lookupPosition > 0
    ? getCurrentLines(lyrics, options.lookupPosition, options.lines)
    : { current: "", upcoming: [], previous: [], index: -1 };

  console.log(JSON.stringify({
    title: options.lookupTitle,
    artist: options.lookupArtist,
    duration: options.lookupDuration,
    synced: lyrics?.synced === true,
    source: lyrics?.source || "",
    sourceId: lyrics?.sourceId || "",
    sourceDuration: lyrics?.sourceDuration || 0,
    sourceAlbum: lyrics?.sourceAlbum || "",
    timingOffset: lyrics?.timingOffset || 0,
    timingOffsetReason: lyrics?.timingOffsetReason || "",
    diagnostics: formatLyricsDiagnostics(lyrics, {
      title: options.lookupTitle,
      artist: options.lookupArtist,
      album: options.lookupAlbum,
      duration: options.lookupDuration,
      position: 0,
      status: "Stopped",
      player: "lookup",
      capturedAtMs: Date.now(),
    }),
    lineCount: lyrics?.lines.length || 0,
    firstLine: lyrics?.lines[0] || null,
    lastLine: lyrics?.lines.at(-1) || null,
    lookupPosition: options.lookupPosition,
    currentAtLookupPosition: lookupCurrent.current,
    currentIndexAtLookupPosition: lookupCurrent.index,
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
