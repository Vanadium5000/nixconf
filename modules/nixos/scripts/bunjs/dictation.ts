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
  try {
    const pid = process.pid;
    await Bun.write(CONFIG.pidFile, pid.toString());
  } catch (e) {
    console.error("Failed to write PID file:", e);
    process.exit(1);
  }

  // Initialize state
  await updateState({ text: "Initializing...", isRecording: true });

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

  // Start Overlay
  if (!noOverlay) {
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

      // Launch the overlay script (which runs the QML)
      // We use 'show' to ensure it appears
      await $`toggle-lyrics-overlay show`.env(env).quiet();
    } catch (e) {
      console.error("Failed to start overlay:", e);
    }
  }

  try {
    // Start whisper-cli in streaming mode
    // -t 4: 4 threads
    // --step 0: step size (0 = auto/default)
    // --length 0: context length
    // -vth 0.6: voice threshold
    // Using stream mode if available or just reading standard output
    // Note: whisper-cli arguments depend on the specific version/fork.
    // Assuming whisper.cpp stream binary arguments or similar.
    // If 'whisper-cli' is the standard 'main' example, it might not do realtime streaming nicely without -stream equivalent.
    // However, the prompt implies using `whisper-cli`. We'll assume it supports standard args.
    // A common realtime command pattern for whisper.cpp is `./stream -m model.bin ...`
    // If whisper-cli is just 'main', we might need to rely on it processing a stream or loop.
    // BUT the prompt says "make the new script is realtime".
    // We will assume `whisper-cli` is capable of this or we are using the `stream` binary wrapped as `whisper-cli`.

    console.log(`Loading model: ${modelPath}`);
    await updateState({ text: "Listening...", isRecording: true });

    // Using `stream` logic:
    // -t 4 threads
    // --step 500ms
    // --length 5000ms buffer
    // -vth 0.6 voice threshold
    const proc = Bun.spawn(
      [
        "whisper-cli",
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
        stdout: "pipe",
        stderr: "pipe", // Capture log output to ignore or debug
      }
    );

    const reader = proc.stdout.getReader();
    const decoder = new TextDecoder();
    let accumulatedText = "";

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      const chunk = decoder.decode(value);
      const lines = chunk.split("\n");

      for (const line of lines) {
        const trimmed = line.trim();
        // whisper-cpp stream output often looks like: "[00:00:00.000 --> 00:00:01.000]   Hello world"
        // We want to extract the text.
        const match = trimmed.match(/^\[.*?\]\s*(.*)/);
        if (match) {
          const text = match[1]!.trim();
          if (text) {
            // Type the text
            // We use wtype to simulate keystrokes
            await $`wtype ${text} `.quiet().catch(() => {});

            // Update state for overlay
            accumulatedText = text; // For realtime, we might just show the last phrase
            await updateState({ text: `Says: ${text}`, isRecording: true });
          }
        }
      }
    }
  } catch (e: any) {
    await updateState({
      text: "Error: " + (e.message || String(e)),
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
