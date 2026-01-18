#!/usr/bin/env bun
import { spawn, connect } from "bun";
import { existsSync, unlinkSync, readFileSync, writeFileSync } from "fs";

// Configuration
const CONFIG = {
  socketPath: "/tmp/dictation.sock", // Legacy cleanup
  statusFile: "/tmp/dictation_status.json",
  pidFile: "/tmp/dictation.pid",
  wyoming: {
    host: "localhost",
    port: 10300,
    rate: 16000,
  },
};

// Types
type Status = {
  active: boolean;
  text: string;
  error: string | null;
};

// --- Main CLI ---

const command = process.argv[2] || "status";

switch (command) {
  case "toggle":
    handleToggle();
    break;
  case "run":
    handleRun();
    break;
  case "status":
    handleStatus();
    break;
  case "daemon":
    // Legacy support: Just clean up state on boot
    cleanupState();
    console.log("Dictation system initialized (on-demand mode)");
    break;
  default:
    console.error("Usage: dictation [toggle|run|status]");
    process.exit(1);
}

// --- Commands ---

function handleStatus() {
  try {
    if (existsSync(CONFIG.statusFile)) {
      const content = readFileSync(CONFIG.statusFile, "utf-8");
      process.stdout.write(content); // Print JSON directly
    } else {
      console.log(JSON.stringify({ active: false, text: "", error: null }));
    }
  } catch (e) {
    console.log(JSON.stringify({ active: false, text: "", error: "Status Read Error" }));
  }
}

function handleToggle() {
  const pid = getRunningPid();
  if (pid) {
    // Stop existing instance
    try {
      process.kill(pid, "SIGINT");
      console.log("Stopped dictation service");
    } catch (e) {
      console.log("Service was stale, cleaning up");
      cleanupState();
    }
  } else {
    // Start new instance
    console.log("Starting dictation service...");
    spawn([process.argv[0], process.argv[1], "run"], {
      stdio: ["ignore", "ignore", "ignore"],
    }).unref();
  }
}

async function handleRun() {
  // 1. Initialization
  const pid = process.pid;
  writeFileSync(CONFIG.pidFile, pid.toString());
  updateStatus({ active: true, text: "", error: null });

  // Cleanup on exit
  const cleanup = () => {
    cleanupState();
    process.exit(0);
  };
  process.on("SIGINT", cleanup);
  process.on("SIGTERM", cleanup);

  // 2. Connect to Wyoming
  let socket;
  try {
    socket = await connect({
      hostname: CONFIG.wyoming.host,
      port: CONFIG.wyoming.port,
      socket: {
        data(_socket, data) {
          handleWyomingData(data);
        },
        error(_socket, error) {
          console.error("Wyoming error:", error);
          updateStatus({ active: false, text: "", error: "Connection Error" });
          cleanup();
        },
        close() {
          cleanup();
        },
      },
    });
  } catch (e) {
    updateStatus({ active: false, text: "", error: "Connection Failed" });
    console.error("Failed to connect to Wyoming:", e);
    // Keep error visible for a moment
    setTimeout(cleanup, 2000);
    return;
  }

  // 3. Send Audio Start
  try {
    socket.write(
      JSON.stringify({
        type: "audio-start",
        data: {
          rate: CONFIG.wyoming.rate,
          width: 2,
          channels: 1,
        },
      }) + "\n"
    );
  } catch (e) {
    cleanup();
    return;
  }

  // Tries pw-record -> parec -> arecord
  const recordCmd = `pw-record --rate ${CONFIG.wyoming.rate} --channels 1 --format s16 - 2>/dev/null || parec --format=s16le --channels=1 --rate=${CONFIG.wyoming.rate} 2>/dev/null || arecord -r ${CONFIG.wyoming.rate} -c 1 -f S16_LE -t raw 2>/dev/null`;
  
  const recorder = spawn(["sh", "-c", recordCmd], {
    stdout: "pipe",
    stderr: "ignore",
  });

  streamAudio(recorder.stdout, socket);

  recorder.exited.then((code) => {
    if (code !== 0 && code !== null) {
        updateStatus({ active: false, text: "", error: "Microphone Error" });
        setTimeout(cleanup, 2000);
    } else {
        cleanup();
    }
  });
}

// --- Helpers ---

function updateStatus(status: Status) {
  try {
    writeFileSync(CONFIG.statusFile, JSON.stringify(status));
  } catch (e) {}
}

function cleanupState() {
  try {
    if (existsSync(CONFIG.pidFile)) unlinkSync(CONFIG.pidFile);
    // Legacy socket cleanup
    if (existsSync(CONFIG.socketPath)) unlinkSync(CONFIG.socketPath);
    
    updateStatus({ active: false, text: "", error: null });
  } catch (e) {}
}

function getRunningPid(): number | null {
  try {
    if (existsSync(CONFIG.pidFile)) {
      const pid = parseInt(readFileSync(CONFIG.pidFile, "utf-8"));
      // Check if actually running
      process.kill(pid, 0); // Throws if not running
      return pid;
    }
  } catch (e) {
    // Process doesn't exist or file is stale
    return null;
  }
  return null;
}

async function streamAudio(readable: any, socket: any) {
  const reader = readable.getReader();
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      
      const header = JSON.stringify({
        type: "audio-chunk",
        data: { rate: CONFIG.wyoming.rate, width: 2, channels: 1 },
        payload_length: value.length,
      }) + "\n";
      
      socket.write(header);
      socket.write(value);
    }
  } catch (e) {
    // Stream broken
  } finally {
    reader.releaseLock();
  }
}

function handleWyomingData(data: Uint8Array) {
  const text = new TextDecoder().decode(data);
  const lines = text.split("\n");
  
  for (const line of lines) {
    if (!line.trim()) continue;
    try {
      const msg = JSON.parse(line);
      if (msg.type === "transcript" && msg.text) {
        updateStatus({ active: true, text: msg.text, error: null });
        spawn(["wtype", msg.text + " "]);
      }
    } catch (e) {}
  }
}
