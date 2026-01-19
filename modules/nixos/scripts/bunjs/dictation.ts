#!/usr/bin/env bun
/**
 * dictation.ts - Realtime dictation using whisper-cpp and lyrics-overlay
 *
 * Usage:
 *   dictation toggle    - Start/Stop the daemon
 *   dictation run       - Run the daemon (internal)
 *   dictation status    - Check if running
 *   dictation source    - Output JSON for the overlay
 *   dictation --help    - Show help
 */

import { $ } from "bun";
import { join } from "node:path";
import { tmpdir, homedir } from "node:os";
import { existsSync, unlinkSync, mkdirSync } from "node:fs";

// --- Configuration ---
const CONFIG = {
  pidFile: join(tmpdir(), "dictation.pid"),
  stateFile: join(tmpdir(), "dictation-state.json"),
  // Default model name to download if no model is found
  defaultModelName: "medium.en",
  // User-local cache directory for downloaded models
  userModelDir: join(homedir(), ".cache", "whisper"),
};

interface State {
  text: string;
  isRecording: boolean;
  error?: string;
}

// --- CLI Argument Parsing ---
const args = Bun.argv.slice(2);
const command = args[0] || "help";

// --- Main Execution ---
switch (command) {
  case "toggle":
    await handleToggle();
    break;
  case "run":
    await handleRun();
    break;
  case "status":
    handleStatus();
    break;
  case "source":
    await handleSource();
    break;
  case "help":
  case "--help":
  case "-h":
    printHelp();
    break;
  default:
    console.error(`Unknown command: ${command}`);
    printHelp();
    process.exit(1);
}

// --- Handlers ---

async function handleToggle() {
  const pid = await getRunningPid();
  if (pid) {
    console.log("Stopping dictation...");
    try {
      process.kill(pid, "SIGTERM");
    } catch {
      // Process might be dead already
    }
    await cleanup();
  } else {
    console.log("Starting dictation...");

    // Spawn the daemon in background
    const logOut = Bun.file("/tmp/dictation.out.log");
    const logErr = Bun.file("/tmp/dictation.err.log");

    Bun.spawn([process.argv[0]!, process.argv[1]!, "run", ...args.slice(1)], {
      stdio: ["ignore", logOut, logErr],
      detached: true,
      env: { ...process.env },
    }).unref();

    // Wait for PID to appear (up to 2 seconds)
    let checks = 0;
    while (checks < 20) {
      await Bun.sleep(100);
      if (await getRunningPid()) {
        console.log("Dictation started.");
        return;
      }
      checks++;
    }
    console.error(
      "Failed to start dictation daemon (timeout). Check /tmp/dictation.err.log"
    );
  }
}

async function handleRun() {
  const pid = process.pid;
  try {
    await Bun.write(CONFIG.pidFile, pid.toString());
  } catch (e) {
    console.error("Failed to write PID file:", e);
    process.exit(1);
  }

  // Initialize state
  await updateState({ text: "Initializing Daemon...", isRecording: true });

  // Cleanup on exit
  const exitHandler = async () => {
    await cleanup();
    process.exit(0);
  };
  process.on("SIGINT", exitHandler);
  process.on("SIGTERM", exitHandler);

  // Parse options for the run command
  const modelArg = getArg("--model");
  const noOverlay = args.includes("--no-overlay");

  // Check dependencies
  try {
    await $`which whisper-stream`.quiet();
  } catch {
    const errorMsg = "Error: whisper-stream not found in PATH";
    console.error(errorMsg);
    await updateState({
      text: errorMsg,
      isRecording: false,
      error: "Missing binary",
    });
    // Keep running briefly so overlay can show error, then exit
    await Bun.sleep(2000);
    process.exit(1);
  }

  // Resolve Model Path
  let modelPath = "";
  try {
    modelPath = await resolveModel(modelArg);
  } catch (e: any) {
    const errorMsg = `Model Error: ${e.message}`;
    console.error(errorMsg);
    await updateState({
      text: "Model Error",
      isRecording: false,
      error: e.message,
    });
    await Bun.sleep(3000);
    process.exit(1);
  }

  // Start Overlay
  if (!noOverlay) {
    await updateState({ text: "Starting Overlay...", isRecording: true });
    try {
      // We hijack the lyrics overlay by setting OVERLAY_COMMAND
      const overlayCmd = `${process.argv[0]} ${process.argv[1]} source`;

      const env = {
        ...process.env,
        OVERLAY_COMMAND: overlayCmd,
        LYRICS_POSITION: "top", // Default to top as requested
        LYRICS_LINES: "3",
        LYRICS_UPDATE_INTERVAL: "100", // Faster updates for dictation
      };

      // Spawn overlay detached so we don't hang waiting for it
      Bun.spawn(["toggle-lyrics-overlay", "show"], {
        env,
        stdio: ["ignore", "ignore", "ignore"],
        detached: true,
      }).unref();
    } catch (e) {
      console.error("Failed to start overlay:", e);
    }
  }

  try {
    const modelName = modelPath.split("/").pop() || "Model";
    console.log(`Loading model: ${modelPath}`);
    await updateState({ text: `Loading ${modelName}...`, isRecording: true });

    // Using `stream` logic via whisper-stream (NOT whisper-cli)
    // whisper-cli expects a file argument, whereas whisper-stream listens to microphone
    const cmd =
      $`whisper-stream -m "${modelPath}" -t 4 --step 500 --length 5000 -vth 0.6 2>&1`.quiet();

    // Watchdog: If we don't start listening within 30 seconds, abort.
    const watchdog = setTimeout(async () => {
      console.error(
        "Timeout: Dictation daemon failed to initialize within 30s."
      );
      await updateState({
        text: "Init Timeout",
        isRecording: false,
        error: "Timeout",
      });
      // We must explicitly kill the child process if it hangs
      proc.kill();
      process.exit(1);
    }, 30000);

    // Use Bun.spawn directly instead of shell template literals for better stream control
    // This allows us to read stderr/stdout as they come, including CR (\r) updates
    const proc = Bun.spawn(
      [
        "whisper-stream",
        "-m",
        modelPath,
        "-t",
        "4",
        "--step",
        "500",
        "--length",
        "5000",
        "-vth",
        "0.6",
      ],
      {
        stdio: ["ignore", "pipe", "pipe"],
      }
    );

    // Read both stdout and stderr
    const streamReader = async (stream: ReadableStream, name: string) => {
      const reader = stream.getReader();
      const decoder = new TextDecoder();
      try {
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          const chunk = decoder.decode(value);

          // Split by newline AND carriage return to handle progress bars/status updates
          const lines = chunk.split(/[\n\r]+/);

          for (const line of lines) {
            const trimmed = line.trim();
            if (!trimmed) continue;

            console.log(`[${name}]: ${trimmed}`);

            // State updates
            if (trimmed.includes("load_backend")) {
              await updateState({ text: "Loading Core...", isRecording: true });
            } else if (trimmed.includes("init: attempt to open")) {
              await updateState({ text: "Init Audio...", isRecording: true });
            } else if (trimmed.includes("whisper_model_load")) {
              await updateState({
                text: "Loading Model...",
                isRecording: true,
              });
            } else if (trimmed.includes("whisper_init_state")) {
              await updateState({ text: "Init Context...", isRecording: true });
            } else if (
              trimmed.includes("computed_timestamps") ||
              trimmed.includes("[Start speaking]") ||
              trimmed.includes("main: processing")
            ) {
              clearTimeout(watchdog);
              await updateState({ text: "Listening...", isRecording: true });
            }

            // Error detection
            if (
              trimmed.includes("failed to open") ||
              trimmed.includes("failed to initialize") ||
              trimmed.includes("found 0 capture devices")
            ) {
              console.error(`Fatal Error detected: ${trimmed}`);
              await updateState({
                text: "Internal Error",
                isRecording: false,
                error: trimmed,
              });
              proc.kill();
              process.exit(1);
            }

            // Standard output matching
            const match = trimmed.match(/^\[.*?\]\s*(.*)/);
            if (match) {
              const text = match[1]!.trim();
              if (text) {
                console.log(`Recognized: ${text}`);
                await $`wtype ${text} `.quiet().catch(() => {});
                await updateState({ text: `Says: ${text}`, isRecording: true });
              }
            }
          }
        }
      } catch (e) {
        console.error(`Error reading ${name}:`, e);
      }
    };

    // Run both readers in parallel
    await Promise.all([
      streamReader(proc.stdout, "stdout"),
      streamReader(proc.stderr, "stderr"),
      proc.exited,
    ]);

    // If the process exits, we're done
    console.log("Dictation process exited.");
    await updateState({ text: "Stopped", isRecording: false });
  } catch (e: any) {
    const errorText = "Error: " + (e.message || String(e));
    console.error(errorText);
    await updateState({
      text: errorText,
      isRecording: false,
      error: String(e),
    });
  }
}

async function handleSource() {
  // Read state and output JSON for the overlay
  try {
    const file = Bun.file(CONFIG.stateFile);
    if (await file.exists()) {
      const state = (await file.json()) as State;

      // Format for lyrics-overlay.qml (WaybarOutput interface compatibility)
      // It expects: { text, tooltip, class, alt }
      const output = {
        text: state.text,
        tooltip: state.isRecording ? "Dictation Active" : "Dictation Stopped",
        class: state.isRecording ? "playing" : "stopped",
        alt: state.isRecording ? "playing" : "stopped",
      };

      console.log(JSON.stringify(output));
    } else {
      console.log(
        JSON.stringify({ text: "...", class: "stopped", alt: "stopped" })
      );
    }
  } catch {
    console.log(
      JSON.stringify({ text: "Error", class: "error", alt: "error" })
    );
  }
}

function handleStatus() {
  // Sync check for PID file
  if (existsSync(CONFIG.pidFile)) {
    console.log("Running");
    process.exit(0);
  } else {
    console.log("Stopped");
    process.exit(1);
  }
}

// --- Model Resolution & Downloading ---

/**
 * Resolves the path to the Whisper model.
 * 1. If explicit path provided, check existence.
 * 2. If explicit name provided (no slashes), check cache or download.
 * 3. If no arg provided, check system default -> user cache -> download default.
 */
async function resolveModel(input: string | null): Promise<string> {
  // Case 1: User provided a path or name
  if (input) {
    // If it looks like a path (contains slashes), expect it to exist
    if (input.includes("/")) {
      if (existsSync(input)) return input;
      throw new Error(`Model file not found at: ${input}`);
    }
    // If it's just a name (e.g., "medium"), ensure it exists in user cache or download it
    return await ensureModelDownloaded(input);
  }

  // Case 2: Fallback to default model in user cache
  return await ensureModelDownloaded(CONFIG.defaultModelName);
}

/**
 * Checks for a model in the user cache directory.
 * If missing, attempts to download it using whisper-cpp-download-ggml-model.
 */
async function ensureModelDownloaded(modelName: string): Promise<string> {
  // The downloader script produces filenames like 'ggml-base.en.bin' from 'base.en'
  const expectedFilename = `ggml-${modelName}.bin`;
  const cachedPath = join(CONFIG.userModelDir, expectedFilename);

  if (existsSync(cachedPath)) {
    console.log(`Using cached model: ${cachedPath}`);
    return cachedPath;
  }

  // Not found, attempt download
  console.log(
    `Model '${modelName}' not found. Attempting download to ${CONFIG.userModelDir}...`
  );
  await updateState({ text: `Downloading ${modelName}...`, isRecording: true });

  // Ensure download tool exists
  try {
    await $`which whisper-cpp-download-ggml-model`.quiet();
  } catch {
    throw new Error("whisper-cpp-download-ggml-model not found in PATH.");
  }

  // Create cache directory
  mkdirSync(CONFIG.userModelDir, { recursive: true });

  try {
    // Run downloader in the cache directory since it downloads to PWD
    // We use 'sh -c' to handle the cd && command pattern safely within bun shell if needed,
    // but Bun shell supports cwd in options or we can just chain commands.
    // The safest way with Bun shell for PWD change is usually:
    // await $`cd ${path} && command` works if it's one shell execution.

    // Note: The downloader script output is verbose, we might want to capture it or show it.
    // We'll let it inherit stdio if attached, but since we are a daemon/background,
    // we should log it.

    await $`cd "${CONFIG.userModelDir}" && whisper-cpp-download-ggml-model "${modelName}"`;

    if (existsSync(cachedPath)) {
      console.log(`Download successful: ${cachedPath}`);
      return cachedPath;
    } else {
      throw new Error("Download completed but model file is missing.");
    }
  } catch (e) {
    throw new Error(`Failed to download model '${modelName}'. Check logs.`);
  }
}

// --- Helpers ---

async function getRunningPid(): Promise<number | null> {
  const file = Bun.file(CONFIG.pidFile);
  if (await file.exists()) {
    try {
      const pid = parseInt(await file.text());
      // Check if process exists
      process.kill(pid, 0);
      return pid;
    } catch {
      return null;
    }
  }
  return null;
}

async function updateState(newState: Partial<State>) {
  try {
    let state: State = { text: "", isRecording: false };
    const file = Bun.file(CONFIG.stateFile);
    if (await file.exists()) {
      try {
        state = await file.json();
      } catch {}
    }

    state = { ...state, ...newState };
    await Bun.write(CONFIG.stateFile, JSON.stringify(state));
  } catch {}
}

async function cleanup() {
  try {
    // Hide overlay
    // We can't easily kill just the overlay from here without the PID,
    // but toggle-lyrics-overlay hide works if it uses a standard mechanism.
    // However, since we started it with a custom environment, we might want to just let it die
    // or explicitly hide it.
    await $`toggle-lyrics-overlay hide`.quiet().catch(() => {});

    if (existsSync(CONFIG.pidFile)) unlinkSync(CONFIG.pidFile);
    if (existsSync(CONFIG.stateFile)) unlinkSync(CONFIG.stateFile);
  } catch {}
}

function getArg(flag: string): string | null {
  const index = args.indexOf(flag);
  if (index !== -1 && index + 1 < args.length) {
    return args[index + 1]!;
  }
  return null;
}

function printHelp() {
  console.log(`
Dictation CLI

Usage: dictation <command> [options]

Commands:
  toggle    Start/Stop the dictation daemon
  run       Run the daemon directly (internal)
  status    Check status
  source    Output JSON for overlay (internal)
  help      Show this help

Options:
  --model <path|name>   Path to model file OR model name (e.g. "medium", default: ${CONFIG.defaultModelName})
  --no-overlay          Disable the visual overlay
`);
}
