import { spawn } from "bun";
import { connect } from "bun";

const SOCKET_PATH = "/tmp/dictation.sock";
const STATUS_FILE = "/tmp/dictation_status.json";
const WYOMING_HOST = "localhost";
const WYOMING_PORT = 10300;
const RATE = 16000;

// Types
type State = {
  active: boolean;
  text: string;
  error: string | null;
};

let state: State = {
  active: false,
  text: "",
  error: null,
};

// Mode handling
const mode = process.argv[2] || "daemon";

if (mode === "daemon") {
  runDaemon();
} else if (mode === "toggle") {
  runClient("TOGGLE");
} else if (mode === "status") {
  runClient("STATUS");
} else if (mode === "monitor") {

  runMonitor();
} else {
  console.error("Unknown mode. Use: daemon, toggle, monitor");
  process.exit(1);
}

// --- Daemon Implementation ---

async function runDaemon() {
  console.log("Starting Dictation Daemon...");
  
  // Cleanup old socket
  try {
    const fs = require("fs");
    if (fs.existsSync(SOCKET_PATH)) fs.unlinkSync(SOCKET_PATH);
  } catch (e) {}

  const clients = new Set<any>();
  let wyomingSocket: any = null;
  let recordProc: any = null;
  let keepAliveTimer: any = null;

  // Broadcast state to all monitor clients
  function broadcast() {
    const msg = JSON.stringify(state) + "\n";
    for (const client of clients) {
      try {
        client.write(msg);
      } catch (e) {
        clients.delete(client);
      }
    }
    // Also write to file for legacy/fallback
    try {
      Bun.write(STATUS_FILE, JSON.stringify(state));
    } catch (e) {}
  }

  // Type text using wtype
  function typeText(text: string) {
    if (!text) return;
    spawn(["wtype", text]);
  }

  // Wyoming Handling
  async function connectWyoming() {
    try {
      if (wyomingSocket) return wyomingSocket;
      
      console.log(`Connecting to Wyoming at ${WYOMING_HOST}:${WYOMING_PORT}...`);
      wyomingSocket = await connect({
        hostname: WYOMING_HOST,
        port: WYOMING_PORT,
        socket: {
          data(socket, data) {
            // Parse Wyoming events (JSON lines)
            const text = new TextDecoder().decode(data);
            const lines = text.split("\n");
            for (const line of lines) {
              if (!line.trim()) continue;
              try {
                const msg = JSON.parse(line);
                handleWyomingMessage(msg);
              } catch (e) {
                // Ignore parsing errors (could be binary payload if we were reading mixed stream)
                // But wyoming-faster-whisper usually sends clean JSON events on the event channel?
                // Actually, we are using the same socket for audio and events.
                // The server might send binary if we requested audio, but we are sending audio.
                // Responses should be JSON.
              }
            }
          },
          error(socket, error) {
            console.error("Wyoming socket error:", error);
            stopDictation("Wyoming Error");
            wyomingSocket = null;
          },
          close() {
            console.log("Wyoming disconnected");
            wyomingSocket = null;
            if (state.active) stopDictation("Wyoming Disconnected");
          },
        },
      });

      // Handshake / Describe?
      // wyoming-faster-whisper expects us to just start sending audio-chunk
      // or audio-start.
      
      return wyomingSocket;
    } catch (e) {
      console.error("Failed to connect to Wyoming:", e);
      state.error = "Connection Failed";
      broadcast();
      return null;
    }
  }

  function handleWyomingMessage(msg: any) {
    if (msg.type === "transcript") {
      const text = msg.text;
      if (text) {
        console.log("Transcript:", text);
        // If it's partial, we might want to show it in UI but not type it yet?
        // faster-whisper usually sends final segments.
        // If is_final is true or missing (default implied final for segment).
        
        // Update UI
        state.text = text;
        broadcast();
        
        // Type it
        typeText(text + " ");
      }
    }
  }

  async function startDictation() {
    if (state.active) return;
    
    const ws = await connectWyoming();
    if (!ws) return;

    state.active = true;
    state.error = null;
    state.text = "";
    broadcast();

    // Send audio-start
    ws.write(JSON.stringify({
      type: "audio-start",
      rate: RATE,
      width: 2,
      channels: 1,
    }) + "\n");

    // Start recording
    // using arecord piped to our handler
    // arecord -r 16000 -c 1 -f S16_LE -t raw
    recordProc = spawn({
      cmd: ["arecord", "-r", RATE.toString(), "-c", "1", "-f", "S16_LE", "-t", "raw", "-B", "10000"], // -B buffer size
      stdout: "pipe",
    });

    readAudioStream(recordProc.stdout, ws);
  }

  async function readAudioStream(stdout: any, ws: any) {
    const reader = stdout.getReader();
    const chunkHeaderBase = {
      type: "audio-chunk",
      rate: RATE,
      width: 2,
      channels: 1,
    };

    try {
      while (state.active) {
        const { done, value } = await reader.read();
        if (done) break;
        if (!state.active) break;
        if (!ws) break;

        // Send chunk
        const header = JSON.stringify({ ...chunkHeaderBase, payload_length: value.length }) + "\n";
        ws.write(header);
        ws.write(value);
      }
    } catch (e) {
      console.error("Audio read error:", e);
    } finally {
      reader.releaseLock();
    }
  }

  async function stopDictation(error: string | null = null) {
    if (!state.active) return;
    
    state.active = false;
    if (error) state.error = error;
    broadcast();

    if (recordProc) {
      recordProc.kill();
      recordProc = null;
    }

    if (wyomingSocket) {
      try {
        wyomingSocket.write(JSON.stringify({ type: "audio-stop" }) + "\n");
        // Don't close socket immediately, wait for final transcripts?
        // For simplicity, we keep socket open for next time, or close it.
        // Wyoming protocol: audio-stop marks end of stream.
      } catch (e) {}
    }
  }

  // Server for CLI/Monitor
  Bun.listen({
    unix: SOCKET_PATH,
    socket: {
      data(socket, data) {
        const msg = new TextDecoder().decode(data).trim();
        if (msg === "TOGGLE") {
          if (state.active) stopDictation();
          else startDictation();
        } else if (msg === "START") {
          startDictation();
        } else if (msg === "STOP") {
          stopDictation();
        }
      },
      open(socket) {
        clients.add(socket);
        // Send current state immediately
        socket.write(JSON.stringify(state) + "\n");
      },
      close(socket) {
        clients.delete(socket);
      },
    },
  });
  
  // Clean exit
  process.on("SIGINT", () => {
    stopDictation();
    try {
        const fs = require("fs");
        if (fs.existsSync(SOCKET_PATH)) fs.unlinkSync(SOCKET_PATH);
    } catch(e) {}
    process.exit(0);
  });
}

// --- Client Implementation ---

async function runClient(command: string) {
  try {
    const socket = await connect({
      unix: SOCKET_PATH,
      socket: {
        open(socket) {
          if (command === "STATUS") {
            // Daemon sends state on connection
          } else {
            socket.write(command);
            // socket.end(); // Don't end immediately if we want to see result, but for TOGGLE we don't care
             if (command === "TOGGLE") {
                // Wait for broadcast? No, just exit
                socket.end();
                process.exit(0);
             }
          }
        },
        data(socket, data) {
          if (command === "STATUS") {
             process.stdout.write(data);
             socket.end();
             process.exit(0);
          }
        },
        error(error) {
          console.error("Failed to connect to daemon. Is it running?");
          process.exit(1);
        }
      }
    });
  } catch (e) {
    console.error("Connection error:", e);
    process.exit(1);
  }
}

async function runMonitor() {
  try {
    const socket = await connect({
      unix: SOCKET_PATH,
      socket: {
        data(socket, data) {
          // Print incoming data (JSON lines) directly to stdout
          process.stdout.write(data);
        },
        error(error) {
          // console.error("Monitor connection error. Retrying...");
          // Retry logic could be handled by the caller (QML Process)
          process.exit(1); 
        },
        close() {
            process.exit(0);
        }
      }
    });
  } catch (e) {
    console.error("Failed to connect to daemon");
    process.exit(1);
  }
}
