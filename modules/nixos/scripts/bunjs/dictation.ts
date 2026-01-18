#!/usr/bin/env bun
import { spawn, connect } from "bun";
import { existsSync, unlinkSync, readFileSync, writeFileSync } from "fs";

// Configuration
const CONFIG = {
  socketPath: "/tmp/dictation.sock", // Legacy cleanup
  statusFile: "/tmp/dictation_status.json",
  pidFile: "/tmp/dictation.pid",
  logFile: "/tmp/dictation.log",
  wyoming: {
    host: "localhost",
    port: 10300,
    rate: 16000,
  },
};

function log(msg: string) {
  const timestamp = new Date().toISOString();
  const line = `[${timestamp}] ${msg}\n`;
  try {
    const fs = require("fs");
    fs.appendFileSync(CONFIG.logFile, line);
  } catch (e) {}
}

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
  case "transcribe":
    if (!process.argv[3]) {
      console.error("Usage: dictation transcribe <file>");
      process.exit(1);
    }
    handleTranscribe(process.argv[3]);
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
    console.error("Usage: dictation [toggle|run|status|transcribe]");
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
    console.log(
      JSON.stringify({ active: false, text: "", error: "Status Read Error" })
    );
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
    spawn([process.argv[0]!, process.argv[1]!, "run"], {
      stdio: ["ignore", "ignore", "ignore"],
    }).unref();
  }
}

async function handleTranscribe(filePath: string) {
  log(`Transcribing file: ${filePath}`);

  // 1. Check file
  if (!require("fs").existsSync(filePath)) {
    console.error("File not found:", filePath);
    process.exit(1);
  }

  // 2. Connect to Wyoming
  let socket;
  try {
    socket = await connect({
      hostname: CONFIG.wyoming.host,
      port: CONFIG.wyoming.port,
      socket: {
        data(_socket, data) {
          const text = new TextDecoder().decode(data);
          const lines = text.split("\n");
          for (const line of lines) {
            if (!line.trim()) continue;
            try {
              const msg = JSON.parse(line);
              if (msg.type === "transcript" && msg.text) {
                console.log(msg.text);
              }
            } catch (e) {}
          }
        },
        error(_socket, error) {
          console.error("Wyoming error:", error);
          process.exit(1);
        },
        close() {
          process.exit(0);
        },
      },
    });
  } catch (e) {
    console.error("Failed to connect to Wyoming:", e);
    process.exit(1);
  }

  // 3. Send Audio Start
  socket.write(
    JSON.stringify({
      type: "audio-start",
      data: {
        rate: CONFIG.wyoming.rate,
        width: 2,
        channels: 1,
        language: "en",
      },
    }) + "\n"
  );

  // 4. Convert and stream using ffmpeg
  const ffmpegCmd = `ffmpeg -i "${filePath}" -f s16le -ac 1 -ar ${CONFIG.wyoming.rate} -`;
  
  const ffmpeg = spawn(["sh", "-c", ffmpegCmd], {
    stdout: "pipe",
    stderr: "pipe",
  });

  (async () => {
    const reader = ffmpeg.stderr.getReader();
    const decoder = new TextDecoder();
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      log(`FFmpeg stderr: ${decoder.decode(value).trim()}`);
    }
  })();

  await streamAudio(ffmpeg.stdout, socket);
  
  log("Finished streaming audio, sending audio-stop");
  socket.write(JSON.stringify({ type: "audio-stop" }) + "\n");
}


async function handleRun() {

  log("Daemon started");
  // 1. Initialization
  const pid = process.pid;
  writeFileSync(CONFIG.pidFile, pid.toString());
  updateStatus({ active: true, text: "", error: null });

  // Cleanup on exit
  const cleanup = () => {
    log("Cleanup triggered");
    cleanupState();
    process.exit(0);
  };
  process.on("SIGINT", cleanup);
  process.on("SIGTERM", cleanup);

  // 2. Connect to Wyoming
  log(`Connecting to Wyoming at ${CONFIG.wyoming.host}:${CONFIG.wyoming.port}`);
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
          log(`Wyoming socket error: ${error}`);
          console.error("Wyoming error:", error);
          updateStatus({ active: false, text: "", error: "Connection Error" });
          cleanup();
        },
        close() {
          log("Wyoming socket closed");
          cleanup();
        },
      },
    });
  } catch (e) {
    log(`Failed to connect to Wyoming: ${e}`);
    updateStatus({ active: false, text: "", error: "Connection Failed" });
    console.error("Failed to connect to Wyoming:", e);
    // Keep error visible for a moment
    setTimeout(cleanup, 2000);
    return;
  }
  log("Connected to Wyoming");

  // 3. Send Audio Start
  try {
    socket.write(
      JSON.stringify({
        type: "audio-start",
        data: {
          rate: CONFIG.wyoming.rate,
          width: 2,
          channels: 1,
          language: "en",
        },
      }) + "\n"
    );
    log("Sent audio-start (en)");
  } catch (e) {
    log(`Failed to send audio-start: ${e}`);
    cleanup();
    return;
  }

  // Tries pw-record -> parec -> arecord
  const recordCmd = `pw-record --rate ${CONFIG.wyoming.rate} --channels 1 --format s16 - || parec --format=s16le --channels=1 --rate=${CONFIG.wyoming.rate} || arecord -r ${CONFIG.wyoming.rate} -c 1 -f S16_LE -t raw`;

  log(`Starting recorder with chain: ${recordCmd}`);
  const recorder = spawn(["sh", "-c", recordCmd], {
    stdout: "pipe",
    stderr: "pipe",
  });

  (async () => {
    const reader = recorder.stderr.getReader();
    const decoder = new TextDecoder();
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      log(`Recorder stderr: ${decoder.decode(value).trim()}`);
    }
  })();

  streamAudio(recorder.stdout, socket);

  recorder.exited.then((code) => {
    log(`Recorder exited with code ${code}`);
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
  let chunkCount = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      if (chunkCount % 50 === 0) {
        const rms = calculateRMS(value);
        log(
          `Sending chunk #${chunkCount} size=${value.length} RMS=${rms.toFixed(
            2
          )}`
        );
      }
      chunkCount++;

      const header =
        JSON.stringify({
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

function calculateRMS(buffer: Uint8Array): number {
  let sum = 0;
  const int16View = new Int16Array(
    buffer.buffer,
    buffer.byteOffset,
    buffer.length / 2
  );
  for (let i = 0; i < int16View.length; i++) {
    sum += int16View[i]! * int16View[i]!;
  }
  return Math.sqrt(sum / int16View.length);
}

function handleWyomingData(data: Uint8Array) {
  const text = new TextDecoder().decode(data);
  const lines = text.split("\n");

  for (const line of lines) {
    if (!line.trim()) continue;
    try {
      const msg = JSON.parse(line);
      log(`Received Wyoming message type: ${msg.type}`);
      if (msg.type === "transcript" && msg.text) {
        log(`Transcript received: "${msg.text}"`);
        updateStatus({ active: true, text: msg.text, error: null });
        spawn(["wtype", msg.text + " "]);
      }
    } catch (e) {
      log(`Error parsing Wyoming message: ${e}`);
    }
  }
}
