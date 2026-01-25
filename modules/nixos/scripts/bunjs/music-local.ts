import { $ } from "bun";
import { join, dirname, basename } from "node:path";
import { exists } from "node:fs/promises";
import { homedir } from "node:os";

// --- Configuration ---
const MUSIC_DIR = join(homedir(), "Shared", "Music");

// --- Types ---
interface MediaItem {
  file: string; // Relative path for MPD
  display: string;
  icon?: string;
  artist?: string;
  title?: string;
}

// --- Helpers ---
async function notify(msg: string, title: string = "Music Local") {
  try {
    await $`notify-send ${title} ${msg}`.nothrow();
  } catch {
    // Ignore notification errors
  }
}

async function getItems(): Promise<MediaItem[]> {
  try {
    // Get all files from MPD
    const output = await $`mpc listall`.text();
    const files = output.split("\n").filter((l) => l.trim());

    if (files.length === 0) return [];

    // Map files to items
    // We try to find a cover.jpg or folder.jpg in the directory
    const items = await Promise.all(
      files.map(async (file) => {
        const fullPath = join(MUSIC_DIR, file);
        const dir = dirname(fullPath);
        
        // Simple display generation (filename based)
        // Ideally we would use 'mpc -f' but listall doesn't support format
        // We could use 'mpc list' but that requires multiple calls
        // Let's stick to path/filename parsing for speed
        const filename = basename(file);
        const name = filename.replace(/\.[^/.]+$/, ""); // strip extension
        
        // Try to parse Artist - Title from filename or path
        // Common formats: "Artist - Title.mp3" or "Artist/Album/Title.mp3"
        let display = name;
        let artist = "";
        
        if (name.includes(" - ")) {
            const parts = name.split(" - ");
            artist = parts[0];
            display = parts.slice(1).join(" - ");
        } else {
            // Try parent directory as artist
            const parent = basename(dir);
            if (parent !== "Music" && parent !== "Shared") {
                artist = parent;
            }
        }

        // Check for cover art
        let icon: string | undefined;
        // Common cover filenames
        const covers = ["cover.jpg", "folder.jpg", "cover.png", "folder.png", "artwork.jpg"];
        
        // This existence check might be heavy if thousands of files
        // But Bun is fast. Let's try.
        for (const cover of covers) {
          const coverPath = join(dir, cover);
          if (await exists(coverPath)) {
            icon = coverPath;
            break;
          }
        }

        return {
          file,
          display: display,
          artist: artist,
          title: display, // roughly
          icon,
        };
      })
    );

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
    const escapedTitle = item.title?.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") || "";
    const escapedArtist = item.artist?.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") || "";
    
    // Format: Title - Artist
    // Using Pango markup for styling
    let display = `<b>${escapedTitle}</b>`;
    if (escapedArtist) {
        display += ` <span size="small" alpha="70%">${escapedArtist}</span>`;
    } else {
        // Fallback to full relative path if parsing failed
        display += ` <span size="small" alpha="50%">${item.file}</span>`;
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
