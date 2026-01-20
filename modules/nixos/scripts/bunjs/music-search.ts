import { $ } from "bun";
import { mkdir } from "node:fs/promises";
import { join } from "node:path";
import { homedir, tmpdir } from "node:os";

// --- Configuration ---
const MUSIC_DIR = join(homedir(), "Shared", "Music");
// Use temp directory for cache so it clears on reboot
const CACHE_DIR = join(tmpdir(), "rofi-music-search");

// --- Types ---
interface MediaItem {
  id: string;
  title: string;
  uploader: string;
  duration_string?: string;
  thumbnail?: string; // URL
  localThumbnail?: string; // Path
  url: string;
  isPlaylist?: boolean;
}

// --- Helpers ---

// Show notification using notify-send
async function notify(msg: string, title: string = "Music Search") {
  try {
    await $`notify-send ${title} ${msg}`.nothrow();
  } catch {
    // Ignore notification errors
  }
}

// Ensure directories exist
async function setupDirs() {
  await mkdir(MUSIC_DIR, { recursive: true });
  await mkdir(CACHE_DIR, { recursive: true });
}

// Validates that a file is a valid JPEG/Image by checking magic bytes
// Returns true if valid, false otherwise (and deletes invalid file)
async function validateThumbnail(path: string): Promise<boolean> {
  try {
    const file = Bun.file(path);
    if (!(await file.exists()) || file.size === 0) return false;

    // Read first few bytes
    const buffer = await file.slice(0, 4).arrayBuffer();
    const view = new Uint8Array(buffer);

    // JPEG: FF D8 FF
    if (
      view.length >= 3 &&
      view[0] === 0xff &&
      view[1] === 0xd8 &&
      view[2] === 0xff
    ) {
      return true;
    }
    // PNG: 89 50 4E 47
    if (
      view.length >= 4 &&
      view[0] === 0x89 &&
      view[1] === 0x50 &&
      view[2] === 0x4e &&
      view[3] === 0x47
    ) {
      return true;
    }

    console.warn(`Invalid image magic bytes for ${path}, deleting...`);
    await $`rm ${path}`.nothrow();
    return false;
  } catch (e) {
    console.error(`Error validating thumbnail ${path}:`, e);
    return false;
  }
}

// Helper to safely parse yt-dlp JSON to MediaItem
function parseMediaItem(
  data: any,
  isPlaylistContext: boolean = false
): MediaItem | null {
  if (!data || !data.id || !data.title) return null;

  const isPlaylist =
    data._type === "playlist" ||
    data.id.startsWith("PL") ||
    data.url?.includes("list=") ||
    isPlaylistContext;

  // Prefer the thumbnail provided by yt-dlp, fallback to construction only for standard videos
  let thumbnail = data.thumbnail || data.thumbnails?.pop()?.url;

  // Sanitize thumbnail URL if needed (sometimes yt-dlp returns webp, we handle that in download)

  if (!thumbnail && !isPlaylist) {
    thumbnail = `https://i.ytimg.com/vi/${data.id}/hqdefault.jpg`;
  }

  let title = data.title;
  if (isPlaylist && !title.startsWith("(Playlist)")) {
    title = `(Playlist) ${title}`;
  }

  return {
    id: data.id,
    title,
    uploader: data.uploader || "Unknown",
    duration_string:
      data.duration_string ||
      data.duration ||
      (isPlaylist ? "Playlist" : "??:??"),
    thumbnail,
    url:
      data.webpage_url ||
      data.url ||
      (isPlaylist
        ? `https://www.youtube.com/playlist?list=${data.id}`
        : `https://www.youtube.com/watch?v=${data.id}`),
    isPlaylist,
  };
}

// --- Search / Fetch Logic ---

async function resolveInput(input: string): Promise<MediaItem[]> {
  const isUrl = input.startsWith("http");

  console.log(`Resolving input: ${input}`);
  const results: MediaItem[] = [];
  const seenKeys = new Set<string>(); // Combine ID + Type or Title + Uploader to dedupe

  const addItem = (item: MediaItem) => {
    if (seenKeys.has(item.id)) return;

    // Strict deduplication by content
    // We treat "Title | Uploader" as a unique key.
    const contentKey = `${item.title.replace("(Playlist) ", "")}|${
      item.uploader
    }`;
    if (seenKeys.has(contentKey)) return;

    results.push(item);
    seenKeys.add(item.id);
    seenKeys.add(contentKey);
  };

  try {
    if (isUrl) {
      // Direct URL (Video or Playlist)
      const isPlaylist = input.includes("list=") && !input.includes("watch?v=");

      console.time("Metadata Fetch");
      await notify(
        isPlaylist
          ? "Fetching playlist metadata..."
          : "Fetching video metadata..."
      );

      const output =
        await $`yt-dlp --flat-playlist -J --ignore-errors ${input}`.text();
      console.timeEnd("Metadata Fetch");

      const data = JSON.parse(output);

      if (
        data._type === "playlist" ||
        (data.entries && Array.isArray(data.entries))
      ) {
        for (const entry of data.entries || []) {
          const item = parseMediaItem(entry);
          if (item) addItem(item);
        }
      } else {
        const item = parseMediaItem(data);
        if (item) addItem(item);
      }
    } else {
      // Search Query - Combined Mode
      console.time("YouTube Search");
      await notify(`Searching for "${input}"...`);

      // 1. Search for videos (ytsearch5 for speed)
      const videoFetch =
        $`yt-dlp --flat-playlist --dump-json "ytsearch5:${input}"`.text();

      // 2. Search for playlists
      const playlistUrl = `https://www.youtube.com/results?search_query=${encodeURIComponent(
        input
      )}&sp=EgIQAw%253D%253D`;
      const playlistFetch =
        $`yt-dlp --flat-playlist --dump-json --playlist-items 1-5 ${playlistUrl}`.text();

      const [videoOutput, playlistOutput] = await Promise.all([
        videoFetch,
        playlistFetch,
      ]);
      console.timeEnd("YouTube Search");

      const lines = [
        ...videoOutput.trim().split("\n"),
        ...playlistOutput.trim().split("\n"),
      ];

      for (const line of lines) {
        if (!line) continue;
        try {
          const data = JSON.parse(line);
          const item = parseMediaItem(data);
          if (item) addItem(item);
        } catch (e) {}
      }
    }
  } catch (e) {
    console.error("Fetch failed:", e);
    await notify("Failed to fetch results", "Error");
  }

  return results;
}

async function fetchThumbnails(items: MediaItem[]) {
  console.log(`Checking thumbnails for ${items.length} items...`);
  // Process in parallel with limit if needed, but 10 items is fine
  const promises = items.map(async (item) => {
    if (!item.thumbnail) return;

    // Clean ID safely
    const cleanId = item.id.replace(/[^a-zA-Z0-9_-]/g, "");
    if (!cleanId) return;

    // We use strict filename to match cache
    const thumbPath = join(CACHE_DIR, `${cleanId}.jpg`);

    // Check if exists AND is valid
    if (await validateThumbnail(thumbPath)) {
      item.localThumbnail = thumbPath;
      return;
    }

    // Download / Convert
    try {
      const tempOne = thumbPath + ".temp";
      // Use User-Agent to avoid 403s on some google URLs
      const response = await fetch(item.thumbnail, {
        headers: {
          "User-Agent":
            "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)",
        },
      });

      if (response.ok) {
        await Bun.write(tempOne, response);
        // Convert to ensure compatibility (rofi likes simple jpg/png)
        // -y overwrite -pix_fmt yuvj420p for max compatibility

        // Scale to height 120 (Rofi usually nice with square or small icons)
        // force jpg
        await $`ffmpeg -y -v error -i ${tempOne} -pix_fmt yuvj420p -vf scale=-1:120 ${thumbPath}`.nothrow();
        await $`rm ${tempOne}`.nothrow();

        if (await validateThumbnail(thumbPath)) {
          item.localThumbnail = thumbPath;
        }
      }
    } catch (e) {
      // Quiet fail
    }
  });

  await Promise.all(promises);
}

// --- Interaction ---

async function showRofiMenu(items: MediaItem[]): Promise<MediaItem | null> {
  let inputString = "";
  const itemMap = new Map<number, MediaItem>();

  items.forEach((item, index) => {
    // Escape Pango markup special chars in title/uploader
    const escapedTitle = item.title
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;");
    const escapedUploader = item.uploader
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;");

    // Format: Title - Uploader (Duration)
    const display = `<b>${escapedTitle}</b> <span size="small" alpha="70%">${escapedUploader} (${item.duration_string})</span>`;

    let line = display;
    if (item.localThumbnail) {
      line += `\0icon\x1f${item.localThumbnail}`;
    }
    inputString += line + "\n";
    itemMap.set(index, item);
  });

  try {
    const rofiCmd = process.env.ROFI_IMAGES || "rofi";
    // Check if it's qs-dmenu to simplify args
    if (rofiCmd.includes("qs-dmenu")) {
      const proc = Bun.spawn(
        [
          rofiCmd,
          "-p",
          "Select Track",
          // qs-dmenu ignores extra flags, so we can leave them or strip them.
          // passing them shouldn't hurt since wrapper handles args in loop
        ],
        { stdin: "pipe", stdout: "pipe" }
      );
      if (proc.stdin) {
        proc.stdin.write(inputString);
        proc.stdin.flush();
        proc.stdin.end();
      }
      const output = await new Response(proc.stdout).text();
      // ... same handling
      const indexStr = output.trim();
      // qs-dmenu returns the original line text (e.g. "Title\0icon..."), 
      // but music-search expects index in Rofi mode "-format i".
      // Wait, music-search uses -format i which returns INDEX.
      // qs-dmenu returns TEXT.
      // We need to map text back to item.
      
      // Let's rewrite this logic for qs-dmenu text return
      if (!indexStr) return null;
      
      // Find item by matching the text line (ignoring icon part if qs-dmenu stripped it in output?)
      // My qs-dmenu returns originalText which includes \0icon...
      // So we just find which key in itemMap has value corresponding to indexStr?
      // No, we need to reverse lookup the item from the string.
      
      // But wait, the existing code uses itemMap.set(index, item).
      // If rofi returns index 0, 1, 2...
      
      // qs-dmenu returns the TEXT content of the line.
      // We can iterate the map values and reconstruction the line to match?
      // Or just map based on Title?
      
      // Simpler: Just search items array for match
      // But inputString construction logic is inside this function.
      
      // Hack:
      // Since I can't easily change the return format of qs-dmenu to index without breaking other scripts,
      // I will search for the item.
      
      // Re-construct the display string for each item to match
       for (const [idx, item] of itemMap.entries()) {
           // We need to reconstruct the exact string we sent
          const escapedTitle = item.title.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
          const escapedUploader = item.uploader.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
          let line = `<b>${escapedTitle}</b> <span size="small" alpha="70%">${escapedUploader} (${item.duration_string})</span>`;
          if (item.localThumbnail) {
              line += `\0icon\x1f${item.localThumbnail}`;
          }
          
          if (line.trim() === indexStr.trim()) {
              return item;
          }
       }
       return null;
    }

    const proc = Bun.spawn(
      [
        rofiCmd,
        "-dmenu",
        "-i",
        "-p",
        "Select Track",
        "-show-icons",
        "-markup-rows",
        "-format",
        "i",
        "-theme-str",
        "element-icon { size: 3.0ch; }", // Make icons reasonable size
      ],
      { stdin: "pipe", stdout: "pipe" }
    );

    if (proc.stdin) {
      proc.stdin.write(inputString);
      proc.stdin.flush();
      proc.stdin.end();
    }

    const output = await new Response(proc.stdout).text();
    const indexStr = output.trim();

    if (!indexStr) return null;
    const index = parseInt(indexStr);
    return itemMap.get(index) || null;
  } catch (e) {
    return null;
  }
}

// --- Download & Play ---

async function downloadAndPlay(items: MediaItem[]) {
  if (items.length === 0) return;

  if (items.length > 1) {
    await notify(`Starting batch download of ${items.length} tracks...`);
  }

  let successCount = 0;
  let failCount = 0;

  for (const [i, item] of items.entries()) {
    const progressPrefix =
      items.length > 1 ? `[${i + 1}/${items.length}] ` : "";
    console.log(`${progressPrefix}Processing: ${item.title}`);

    const outputTemplate = join(MUSIC_DIR, "%(title)s [%(id)s].%(ext)s");

    await notify(`${progressPrefix}Downloading: ${item.title}`);

    // Download Video
    // Use nothrow() to handle errors manually
    const dlProc =
      await $`yt-dlp -x --audio-format mp3 --audio-quality 0 --embed-thumbnail --add-metadata --ignore-errors -o ${outputTemplate} --no-playlist ${item.url}`
        .nothrow()
        .quiet();

    if (dlProc.exitCode !== 0) {
      console.error(
        `${progressPrefix}Failed to download: ${item.title} (Exit Code: ${dlProc.exitCode})`
      );
      // Try to read stderr if available to show reason
      const stderr = dlProc.stderr.toString().trim();
      if (stderr) console.error(stderr.split("\n")[0]); // Just first line

      await notify(`Skipped: ${item.title}`, "Download Failed");
      failCount++;
      continue;
    }

    // Get filename for MPD
    // If download worked, getting filename should usually work
    try {
      let filename =
        await $`yt-dlp --get-filename -x --audio-format mp3 -o ${outputTemplate} --no-playlist ${item.url}`.text();
      filename = filename.trim();

      if (!filename.endsWith(".mp3")) {
        filename = filename.replace(/\.[^/.]+$/, "") + ".mp3";
      }

      await addToMpd(filename);
      successCount++;
    } catch (e) {
      console.error(`Failed to get filename for ${item.title}`, e);
      failCount++;
    }
  }

  if (failCount > 0) {
    await notify(
      `Batch finished. ${successCount} succeeded, ${failCount} failed.`
    );
  } else {
    await notify("All downloads completed.");
  }
}

async function addToMpd(fullPath: string) {
  const relPath = fullPath.startsWith(MUSIC_DIR)
    ? fullPath.slice(MUSIC_DIR.length + 1)
    : fullPath;

  // Force update specific file if possible, or folder
  // mpc update requires path relative to music dir
  await $`mpc update --wait`.nothrow();

  const addRes = await $`mpc add "${relPath}"`.nothrow();
  if (addRes.exitCode !== 0) {
    console.warn(
      `Failed to add ${relPath} to MPD (exit ${addRes.exitCode}). Retrying update...`
    );
    await $`mpc update --wait`.nothrow();
    await $`mpc add "${relPath}"`.nothrow();
  }
}

// --- Main ---

async function main() {
  await setupDirs();

  let query = Bun.argv[2];

  if (!query) {
    try {
      // Simple input box
      query = (
        await $`qs-dmenu -p "Search YouTube"`.text()
      ).trim();
    } catch {
      return;
    }
  }

  if (!query) return;

  const items = await resolveInput(query);

  if (items.length === 0) {
    await notify("No results found.");
    return;
  }

  const isDirectUrl = query.startsWith("http");

  if (isDirectUrl) {
    await downloadAndPlay(items);
  } else {
    await fetchThumbnails(items);
    const selected = await showRofiMenu(items);
    if (selected) {
      await downloadAndPlay([selected]);
    }
  }

  await $`mpc random on`.nothrow();
}

main().catch((e) => {
  console.error(e);
  notify(`Fatal Error: ${e.message}`);
});
