#!/usr/bin/env bun
import { $ } from "bun";
import { existsSync, readFileSync, writeFileSync, unlinkSync } from "fs";

const CONFIG = {
  pidFile: "/tmp/dictation.pid",
  logFile: "/tmp/dictation.log",
  modelPath:
    process.env.WHISPER_MODEL_PATH ||
    "/var/cache/ollama/whisper/ggml-base.en.bin",
  overlay: {
    script: "toggle-lyrics-overlay",
    position: "top",
  },
};

type Args = {
  overlay?: boolean;
  model?: string;
  language?: string;
};

const command = process.argv[2] || "help";
const args = parseArgs();

switch (command) {
  case "toggle":
    await handleToggle();
    break;
  case "run":
    await handleRun(args);
    break;
  case "status":
    handleStatus();
    break;
  case "help":
    printHelp();
    break;
  default:
    console.error(`Unknown command: ${command}`);
    printHelp();
    process.exit(1);
}

async function handleToggle() {
  const pid = getRunningPid();
  if (pid) {
    console.log("Stopping dictation service...");
    try {
      process.kill(pid, "SIGTERM");
    } catch (e) {
      console.log("Service was stale, cleaning up.");
      cleanupState();
    }
  } else {
    console.log("Starting dictation service...");
    Bun.spawn([process.argv[0]!, process.argv[1]!, "run"], {
      stdio: ["ignore", "ignore", "ignore"],
      detached: true,
    });
  }
}

async function handleRun(options: Args) {
  const pid = process.pid;
  writeFileSync(CONFIG.pidFile, pid.toString());
  log(`Daemon started (PID: ${pid})`);

  const cleanup = async () => {
    log("Cleanup triggered");
    if (options.overlay !== false) {
      try {
        await $`${CONFIG.overlay.script} hide`.quiet();
      } catch (e) {}
    }
    cleanupState();
    process.exit(0);
  };

  process.on("SIGINT", cleanup);
  process.on("SIGTERM", cleanup);

  if (options.overlay !== false) {
    try {
      log("Showing overlay...");
      const env = {
        ...process.env,
        LYRICS_POSITION: CONFIG.overlay.position,
        LYRICS_LINES: "1",
      };
      await $`${CONFIG.overlay.script} show`.env(env).quiet();
    } catch (e) {
      log(`Failed to show overlay: ${e}`);
    }
  }

  try {
    const model = options.model || CONFIG.modelPath;
    log(`Starting recognition with model: ${model}`);

    const proc = Bun.spawn(
      [
        "bash",
        "-c",
        `whisper-cli -m "${model}" -l en -t 4 --step 500 --length 5000 -vth 0.6`,
      ],
      {
        stdout: "pipe",
        stderr: "pipe",
      }
    );

    const reader = proc.stdout.getReader();
    const decoder = new TextDecoder();

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      const text = decoder.decode(value).trim();
      if (text) {
        log(`Recognized: ${text}`);
        await $`wtype ${text} `.quiet();
      }
    }

    await proc.exited;
  } catch (e) {
    log(`Error in pipeline: ${e}`);
  } finally {
    cleanup();
  }
}

function handleStatus() {
  const pid = getRunningPid();
  if (pid) {
    console.log(`Running (PID: ${pid})`);
  } else {
    console.log("Stopped");
  }
}

function parseArgs(): Args {
  const args: Args = {};
  const raw = process.argv.slice(3);
  for (let i = 0; i < raw.length; i++) {
    const arg = raw[i];
    if (arg === "--no-overlay") args.overlay = false;
    else if (arg === "--model" && raw[i + 1]) args.model = raw[++i];
  }
  return args;
}

function getRunningPid(): number | null {
  try {
    if (existsSync(CONFIG.pidFile)) {
      const pid = parseInt(readFileSync(CONFIG.pidFile, "utf-8"));
      process.kill(pid, 0);
      return pid;
    }
  } catch (e) {
    return null;
  }
  return null;
}

function cleanupState() {
  try {
    if (existsSync(CONFIG.pidFile)) unlinkSync(CONFIG.pidFile);
  } catch (e) {}
}

function log(msg: string) {
  const timestamp = new Date().toISOString();
  try {
    const fs = require("fs");
    fs.appendFileSync(CONFIG.logFile, `[${timestamp}] ${msg}\n`);
  } catch (e) {}
}

function printHelp() {
  console.log(`
Dictation CLI

Usage: dictation <command> [options]

Commands:
  toggle    Start/Stop the dictation daemon
  run       Run the daemon directly (foreground)
  status    Check status
  help      Show this help

Options:
  --no-overlay   Disable the visual overlay
  --model <path> Path to GGML model file
  `);
}
