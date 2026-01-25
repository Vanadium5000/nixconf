import { $ } from "bun";
import { join, dirname, basename, extname } from "node:path";
import { exists, mkdir } from "node:fs/promises";
import { homedir } from "node:os";

// --- Configuration ---
const MUSIC_DIR = join(homedir(), "Shared", "Music");
const CACHE_DIR = join(homedir(), ".cache", "qs-music-local");

// --- Types ---
interface MediaItem {
  file: string; // Relative path for MPD
  display: string;
  artist?: string;
  title?: string;
  icon?: string;
}

// --- Helpers ---
async function notify(msg: string, title: string = "Music Local") {
  try {
    await $`notify-send ${title} ${msg}`.nothrow();
  } catch {
    // Ignore notification errors
  }
}

// Hash function for cache filenames (simple numeric hash to hex)
function hashString(str: string): string {
  let hash = 0;
  for (let i = 0; i < str.length; i++) {
    const char = str.charCodeAt(i);
    hash = (hash << 5) - hash + char;
    hash |= 0; // Convert to 32bit integer
  }
  return (hash >>> 0).toString(16); // Unsigned hex
}

async function extractThumbnail(inputFile: string, cacheFile: string): Promise<boolean> {
    try {
        // Extract and resize to 120px height (matches music-search.ts)
        // -pix_fmt yuvj420p ensures high compatibility (deprecated but useful for thumb generation)
        // -an: no audio
        // -v error: quiet
        // -y: overwrite
        const res = await $`ffmpeg -y -v error -i ${inputFile} -an -vf scale=-1:120 -pix_fmt yuvj420p ${cacheFile}`.nothrow();
        return res.exitCode === 0;
    } catch (e) {
        return false;
    }
}

async function getItems(): Promise<MediaItem[]> {
  try {
    // Ensure cache dir exists
    await mkdir(CACHE_DIR, { recursive: true });

    // Get files with metadata from MPD
    // Format: file [TAB] artist [TAB] title
    // We use search filename "" to get all files
    const output = await $`mpc -f "%file%\t%artist%\t%title%" search filename ""`.text();
    const lines = output.split("\n").filter((l) => l.trim());

    if (lines.length === 0) return [];

    const items: MediaItem[] = [];
    const queue: Promise<void>[] = [];
    const CONCURRENCY = 8; // Limit ffmpeg processes

    for (const line of lines) {
        // Wait if queue is full
        if (queue.length >= CONCURRENCY) {
            await Promise.race(queue);
        }

        const task = (async () => {
            const parts = line.split("\t");
            const file = parts[0];
            let artist = parts[1] || "";
            let title = parts[2] || "";
            
            const fullPath = join(MUSIC_DIR, file);
            const dir = dirname(fullPath);

            // Fallback parsing if tags are missing
            if (!title) {
                const filename = basename(file);
                const name = filename.replace(/\.[^/.]+$/, "");
                
                // Try "Artist - Title" pattern
                if (name.includes(" - ")) {
                    const p = name.split(" - ");
                    artist = artist || p[0];
                    title = p.slice(1).join(" - ");
                } else {
                    title = name;
                }
            }

            // Cleanup "Unknown"
            if (artist === "Unknown Artist") artist = "";
            if (title === "Unknown Title") title = basename(file);

            // --- Thumbnail Logic ---
            let icon: string | undefined;
            
            // 1. Check for local directory cover (fastest, high quality)
            const covers = ["cover.jpg", "folder.jpg", "cover.png", "folder.png", "artwork.jpg"];
            for (const cover of covers) {
                const coverPath = join(dir, cover);
                if (await exists(coverPath)) {
                    icon = coverPath;
                    break;
                }
            }

            // 2. Check for embedded art (extract if needed)
            if (!icon) {
                // Create unique cache name based on file path
                const cacheName = hashString(file) + ".jpg";
                const cachePath = join(CACHE_DIR, cacheName);
                
                if (await exists(cachePath)) {
                    icon = cachePath;
                } else {
                    // Extract asynchronously
                    // We treat this as a "best effort" - if it fails or takes too long, we might show menu without it
                    // But here we await it to populate the menu correctly first time
                    const success = await extractThumbnail(fullPath, cachePath);
                    if (success) {
                        icon = cachePath;
                    }
                }
            }

            items.push({
                file,
                display: artist ? `${title} - ${artist}` : title,
                artist,
                title,
                icon
            });
        })();

        queue.push(task);
        // Remove from queue when done
        task.finally(() => {
            queue.splice(queue.indexOf(task), 1);
        });
    }

    // Wait for remaining tasks
    await Promise.all(queue);

    return items;
  } catch (e) {
    console.error("Failed to list music:", e);
    return [];
  }
}

async function showMenu(items: MediaItem[]): Promise<MediaItem | null> {
  let inputString = "";
  // Map both full line and clean display to item to handle dmenu stripping
  const itemMap = new Map<string, MediaItem>();

  items.forEach((item) => {
    // Escape Pango markup special chars
    const escapedTitle = (item.title || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    const escapedArtist = (item.artist || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    
    // Format: Title - Artist
    // Using Pango markup for styling
    let display = `<b>${escapedTitle}</b>`;
    if (escapedArtist) {
        display += ` <span size="small" alpha="70%">${escapedArtist}</span>`;
    } else {
        // Fallback
        if (!escapedTitle) display = `<b>${item.file}</b>`;
    }

    let line = display;
    if (item.icon) {
      line += `\0icon\x1f${item.icon}`;
    }
    inputString += line + "\n";
    
    // Key mapping:
    // 1. Full line (ideal)
    itemMap.set(line.trim(), item);
    // 2. Display part only (fallback if icon stripped)
    itemMap.set(display.trim(), item);
  });

  try {
    const menuCmd = process.env.QS_MENU || "qs-dmenu";
    
    const proc = Bun.spawn(
      [
        menuCmd,
        "-p",
        "Local Music",
      ],
      {
        stdin: "pipe",
        stdout: "pipe",
        env: {
          ...process.env,
          DMENU_VIEW: "grid",
          DMENU_GRID_COLS: "3",
          DMENU_ICON_SIZE: "256",
        },
      }
    );

    if (proc.stdin) {
      proc.stdin.write(inputString);
      proc.stdin.flush();
      proc.stdin.end();
    }

    const output = await new Response(proc.stdout).text();
    const indexStr = output.trim();

    if (!indexStr) return null;

    if (itemMap.has(indexStr)) {
        return itemMap.get(indexStr)!;
    }
    
    // Last ditch: substring match if display was mangled
    // (Unlikely with the strict Map logic, but safety net)
    for (const [key, item] of itemMap) {
        if (key.includes(indexStr) || indexStr.includes(key)) {
            return item;
        }
    }
    
    return null;
  } catch (e) {
    return null;
  }
}


async function play(item: MediaItem) {
  await notify(`Playing: ${item.display}`);
  
  // Logic:
  // 1. Clear queue
  // 2. Add ALL music
  // 3. Shuffle
  // 4. Play the selected song (find it in the shuffled queue)
  
  try {
      await $`mpc clear`.nothrow();
      await $`mpc add /`.nothrow();
      await $`mpc shuffle`.nothrow();
      // searchplay filename finds the song in queue and plays it
      await $`mpc searchplay filename "${item.file}"`.nothrow();
  } catch (e) {
      console.error("Playback failed:", e);
      await notify("Playback failed", "Error");
  }
}

async function main() {
  const items = await getItems();

  if (items.length === 0) {
    await notify("No music found in MPD library");
    return;
  }

  const selected = await showMenu(items);
  if (selected) {
    await play(selected);
  }
}

main().catch((e) => {
  console.error(e);
  notify(`Fatal Error: ${e.message}`);
});
