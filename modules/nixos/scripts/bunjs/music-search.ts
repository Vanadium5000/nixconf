import { $ } from "bun";
import { mkdir } from "node:fs/promises";
import { join } from "node:path";
import { homedir } from "node:os";

// --- Configuration ---
const MUSIC_DIR = join(homedir(), "Shared", "Music");
const CACHE_DIR = join(homedir(), ".cache", "rofi-music-search");

// --- Types ---
interface SearchResult {
  id: string;
  title: string;
  uploader: string;
  duration_string: string;
  thumbnail?: string; // URL
  localThumbnail?: string; // Path
}

// --- Helpers ---

// Show notification
async function notify(msg: string, title: string = "Music Search") {
  await $`notify-send ${title} ${msg}`;
}

// Ensure directories exist
async function setupDirs() {
  await mkdir(MUSIC_DIR, { recursive: true });
  await mkdir(CACHE_DIR, { recursive: true });
}

// --- Main Logic ---

async function searchYouTube(query: string): Promise<SearchResult[]> {
  console.log("Searching for:", query);
  // Using ytsearch10 as requested
  const output =
    await $`yt-dlp --dump-json --default-search "ytsearch10" --no-playlist --ignore-errors ${query}`.text();

  const results: SearchResult[] = [];

  const lines = output.trim().split("\n");
  for (const line of lines) {
    if (!line) continue;
    try {
      const data = JSON.parse(line);
      results.push({
        id: data.id,
        title: data.title,
        uploader: data.uploader || "Unknown",
        duration_string: data.duration_string || "??:??",
        thumbnail: data.thumbnail,
      });
    } catch (e) {
      console.error("Failed to parse line:", e);
    }
  }

  return results;
}

async function fetchThumbnails(results: SearchResult[]) {
  const promises = results.map(async (res) => {
    if (!res.thumbnail) return;
    const thumbPath = join(CACHE_DIR, `${res.id}.jpg`);
    const file = Bun.file(thumbPath);

    if (await file.exists()) {
      res.localThumbnail = thumbPath;
      return;
    }

    try {
      const response = await fetch(res.thumbnail);
      if (response.ok) {
        await Bun.write(thumbPath, response);
        res.localThumbnail = thumbPath;
      }
    } catch (e) {
      console.error(`Failed to download thumb for ${res.id}`, e);
    }
  });

  await Promise.all(promises);
}

async function showRofiMenu(
  results: SearchResult[]
): Promise<SearchResult | null> {
  let inputString = "";
  const map = new Map<string, SearchResult>();

  for (const res of results) {
    const display = `${res.title} - ${res.uploader} (${res.duration_string})`;

    let line = display;
    if (res.localThumbnail) {
      line += `\0icon\x1f${res.localThumbnail}`;
    }
    inputString += line + "\n";
    map.set(display, res);
  }

  try {
    // Bun $ allows piping input via stdin
    // We can interpret stdout as text directly
    // Note: rofi exits with 1 if cancelled, so we need to catch partial failures/exits if we want to handle cancel gracefully?
    // Actually bun shell throws on non-zero exit by default.
    const selection =
      await $`echo ${inputString} | rofi -dmenu -i -p "Select Track" -show-icons -markup-rows`.text();
    return map.get(selection.trim()) || null;
  } catch (e) {
    // Rofi returns 1 on cancel usually.
    return null;
  }
}

async function downloadTrack(result: SearchResult): Promise<string> {
  await notify(`Downloading: ${result.title}`);
  const outputTemplate = join(MUSIC_DIR, "%(title)s.%(ext)s");

  // High quality audio
  // Just run it.
  await $`yt-dlp -x --audio-format mp3 --audio-quality 0 -o ${outputTemplate} --no-playlist ${result.id}`;

  // Get filename
  // Get filename
  let filename =
    await $`yt-dlp --get-filename -x --audio-format mp3 -o ${outputTemplate} --no-playlist ${result.id}`.text();
  filename = filename.trim();

  // yt-dlp --get-filename returns the pre-converted extension (e.g. .webm)
  // We force it to .mp3 because we used -x --audio-format mp3
  if (!filename.endsWith(".mp3")) {
    const lastDotIndex = filename.lastIndexOf(".");
    if (lastDotIndex !== -1) {
      filename = filename.substring(0, lastDotIndex) + ".mp3";
    } else {
      filename = filename + ".mp3";
    }
  }

  return filename;
}

async function playWithMpd(fullPath: string) {
  const relPath = fullPath.startsWith(MUSIC_DIR)
    ? fullPath.slice(MUSIC_DIR.length + 1)
    : fullPath;

  console.log("Refreshing MPD database...");
  await $`mpc update --wait`.nothrow(); // Don't crash if wait fails

  console.log(`Adding "${relPath}" to playlist`);

  // Try to find exact match in LS first to verify DB has it
  // This helps debug if it's a DB update lag or a path mismatch
  // mpc ls searches from root.
  // escaping for bun shell: variables are auto-escaped.

  let retries = 3;
  while (retries > 0) {
    const addRes = await $`mpc add ${relPath}`.nothrow();
    if (addRes.exitCode === 0) break;

    console.log(`mpc add failed, retrying update... (${retries} left)`);
    // Update whole DB to be sure or path specific
    await $`mpc update --wait`.nothrow();
    await new Promise((r) => setTimeout(r, 1000));
    retries--;
  }

  await $`mpc random on`;

  await notify(`Added to queue: ${relPath}`);
}

async function main() {
  await setupDirs();

  let query = Bun.argv[2];

  if (!query) {
    try {
      query = (await $`rofi -dmenu -p "Search Music" -lines 0`.text()).trim();
    } catch {
      return; // Cancelled
    }
  }

  if (!query) return;

  await notify(`Searching for "${query}"...`);

  const results = await searchYouTube(query);
  if (results.length === 0) {
    await notify("No results found.");
    return;
  }

  await fetchThumbnails(results);

  const selected = await showRofiMenu(results);
  if (!selected) return;

  const filename = await downloadTrack(selected);

  await playWithMpd(filename);
}

main().catch((e) => {
  console.error(e);
  notify(`Error: ${e.message}`, "Search Failed");
});
