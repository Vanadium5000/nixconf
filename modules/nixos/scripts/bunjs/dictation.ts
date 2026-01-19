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
import { tmpdir } from "node:os";
import { existsSync, unlinkSync } from "node:fs";

// --- Configuration ---
const CONFIG = {
  pidFile: join(tmpdir(), "dictation.pid"),
  stateFile: join(tmpdir(), "dictation-state.json"),
  // Default model path (can be overridden via --model)
  defaultModel: "/var/cache/ollama/whisper/ggml-base.en.bin",
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
  const modelPath = getArg("--model") || CONFIG.defaultModel;
  const noOverlay = args.includes("--no-overlay");

  // Check dependencies
  try {
    await $`which whisper-cli`.quiet();
  } catch {
    const errorMsg = "Error: whisper-cli not found in PATH";
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

    // Using `stream` logic via whisper-cli
    // We iterate over lines directly using Bun Shell's streaming capability
    const cmd =
      $`whisper-cli -m "${modelPath}" -t 4 --step 500 --length 5000 -vth 0.6`.quiet();

    let accumulatedText = "";

    for await (const line of cmd.lines()) {
      const trimmed = line.trim();
      // whisper-cpp stream output often looks like: "[00:00:00.000 --> 00:00:01.000]   Hello world"
      const match = trimmed.match(/^\[.*?\]\s*(.*)/);
      if (match) {
        const text = match[1]!.trim();
        if (text) {
          console.log(`Recognized: ${text}`);

          // Type the text
          await $`wtype ${text} `.quiet().catch(() => {});

          // Update state for overlay
          accumulatedText = text;
          await updateState({ text: `Says: ${text}`, isRecording: true });
        }
      } else if (trimmed.includes("loading model")) {
        await updateState({ text: "Loading core...", isRecording: true });
      }
    }
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
  --model <path>   Path to Whisper model (default: ${CONFIG.defaultModel})
  --no-overlay     Disable the visual overlay
`);
}
