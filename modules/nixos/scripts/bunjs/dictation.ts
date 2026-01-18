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
    try {
      ws.write(JSON.stringify({
        type: "audio-start",
        data: {
            rate: RATE,
            width: 2,
            channels: 1,
        }
      }) + "\n");
    } catch (e) {
      console.error("Failed to send audio-start:", e);
      stopDictation("Wyoming Error");
      return;
    }

    // Start recording
    // Try parec (PulseAudio/PipeWire) first, then fallback to arecord (ALSA)
    try {
        const fs = require("fs");
        // Check if parec is available (primitive check by spawning or checking path? 
        // We'll just try spawning parec, if it fails immediately/errors, we could fallback? 
        // But spawn doesn't throw if exe missing in bun, it throws on await or exit? 
        // Actually spawn throws if command not found.
        
        try {
             recordProc = spawn({
                cmd: ["parec", "--format=s16le", "--channels=1", "--rate=" + RATE.toString(), "--latency=1024"],
                stdout: "pipe",
                stderr: "pipe", 
             });
             console.log("Using parec for recording");
        } catch (e) {
             console.log("parec not found/failed, falling back to arecord");
             throw e; // trigger fallback
        }
    } catch (e) {
         try {
            recordProc = spawn({
                cmd: ["arecord", "-r", RATE.toString(), "-c", "1", "-f", "S16_LE", "-t", "raw"],
                stdout: "pipe",
                stderr: "pipe", 
            });
            console.log("Using arecord for recording");
         } catch (e2) {
             console.error("Failed to spawn recorder:", e2);
             stopDictation("Record Error");
             return;
         }
    }

    // Log stderr
    (async () => {
        const reader = recordProc.stderr.getReader();
        const decoder = new TextDecoder();
        while (true) {
            const { done, value } = await reader.read();
            if (done) break;
            console.error("recorder stderr:", decoder.decode(value).trim());
        }
    })();

    // Check exit
    recordProc.exited.then((code: number) => {
        console.log("recorder exited with code:", code);
        // If it exits too fast (e.g. within 1 second) and we haven't stopped manually, it's an error.
        if (state.active) stopDictation("Recorder Exited");
    });

    readAudioStream(recordProc.stdout, ws);
  }

  async function readAudioStream(stdout: any, ws: any) {
    const reader = stdout.getReader();
    const chunkType = "audio-chunk";

    try {
      while (state.active) {
        const { done, value } = await reader.read();
        if (done) break;
        if (!state.active) break;
        
        // Check if socket is still open
        if (!ws || (ws.readyState && ws.readyState !== "open")) { 
             break;
        }

        // Send chunk
        try {
            const header = JSON.stringify({ 
                type: chunkType,
                data: {
                    rate: RATE,
                    width: 2,
                    channels: 1,
                },
                payload_length: value.length 
            }) + "\n";
            ws.write(header);
            ws.write(value);
            // Flush? Bun writes are usually immediate/buffered.
        } catch (e) {
            console.error("Wyoming write error:", e);
            break;
        }
      }
    } catch (e) {
      console.error("Audio read error:", e);
    } finally {
      reader.releaseLock();
      if (state.active) stopDictation("Stream Ended");
    }
  }

  async function stopDictation(error: string | null = null) {
    if (!state.active) return;
    
    console.log(`Stopping dictation. Reason: ${error || "User Request"}`);
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
        // Wyoming protocol: audio-stop marks end of stream.
        // We will keep the socket open if possible, but simpler to just close and reconnect on next session
        // to avoid state desync.
        wyomingSocket.end(); 
        wyomingSocket = null;
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
