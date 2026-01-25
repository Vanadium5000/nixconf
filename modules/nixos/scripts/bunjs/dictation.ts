#!/usr/bin/env bun
/**
 * dictation.ts - Realtime dictation and media transcription using whisper-cpp
 *
 * Usage:
 *   dictation toggle           - Start/Stop live dictation daemon
 *   dictation run              - Run daemon directly (internal)
 *   dictation status           - Output JSON status for waybar
 *   dictation source           - Output JSON for overlay (internal)
 *   dictation transcribe <file> - Transcribe media file
 *   dictation --help           - Show help
 */

import { $ } from "bun";
import { join, basename, extname } from "node:path";
import { tmpdir, homedir } from "node:os";
import { existsSync } from "node:fs";
import { mkdir, unlink, appendFile } from "node:fs/promises";

const HOST = process.env.HOST || "unknown";
const IS_MACBOOK = HOST === "macbook";

let smoothedVolume = 0;

const CONFIG = {
  pidFile: join(tmpdir(), "dictation.pid"),
  stateFile: join(tmpdir(), "dictation-state.json"),
  logFile: join(tmpdir(), "dictation.log"),
  outLog: join(tmpdir(), "dictation.out.log"),
  errLog: join(tmpdir(), "dictation.err.log"),
  configDir: join(homedir(), ".config", "dictation"),
  configFile: join(homedir(), ".config", "dictation", "config.json"),
  defaultModelName: IS_MACBOOK ? "base.en" : "medium.en",
  userModelDir: join(homedir(), ".cache", "whisper"),
  supportedAudio: [".mp3", ".wav", ".flac", ".ogg", ".m4a", ".aac", ".wma"],
  supportedVideo: [".mp4", ".mkv", ".avi", ".mov", ".webm", ".wmv", ".flv"],
} as const;

interface UserConfig {
  inputDevice?: string; // SDL device name (e.g., "Apple Audio Device BuiltinMic")
}

interface AudioDevice {
  sdlId: number;
  name: string;
}

interface State {
  text: string;
  isRecording: boolean;
  mode: "idle" | "live" | "transcribe" | "downloading" | "error";
  error?: string;
  progress?: string;
  file?: string;
  startTime?: number;
  volume?: number;
}

interface TranscriptSegment {
  start: number;
  end: number;
  text: string;
}

type SubtitleFormat = "srt" | "vtt" | "txt";

async function log(
  level: "INFO" | "WARN" | "ERROR",
  msg: string,
  data?: unknown
) {
  const ts = new Date().toISOString().slice(11, 23);
  const line = `[${ts}] ${level}: ${msg}${
    data !== undefined ? ` ${JSON.stringify(data)}` : ""
  }`;
  try {
    await appendFile(CONFIG.logFile, line + "\n");
  } catch {}
  if (level === "ERROR") console.error(line);
}

const args = Bun.argv.slice(2);
const command = args[0] || "help";

switch (command) {
  case "toggle":
    await handleToggle();
    break;
  case "run":
    await handleRun();
    break;
  case "status":
    await handleStatus();
    break;
  case "source":
    await handleSource();
    break;
  case "transcribe":
    await handleTranscribe();
    break;
  case "select-device":
    await handleSelectDevice();
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

async function handleToggle() {
  const pid = await getRunningPid();
  if (pid) {
    await log("INFO", "Stopping daemon", { pid });
    try {
      process.kill(pid, "SIGTERM");
    } catch {}
    await cleanup();
    console.log("Dictation stopped.");
  } else {
    await log("INFO", "Starting daemon");
    const logOut = Bun.file(CONFIG.outLog);
    const logErr = Bun.file(CONFIG.errLog);

    Bun.spawn([process.argv[0]!, process.argv[1]!, "run", ...args.slice(1)], {
      stdio: ["ignore", logOut, logErr],
      detached: true,
      env: { ...process.env },
    }).unref();

    for (let i = 0; i < 30; i++) {
      await Bun.sleep(100);
      if (await getRunningPid()) {
        console.log("Dictation started.");
        return;
      }
    }
    console.error(`Failed to start. Check ${CONFIG.errLog}`);
    process.exit(1);
  }
}

async function handleRun() {
  const pid = process.pid;
  await log("INFO", "Daemon started", {
    pid,
    host: HOST,
    model: CONFIG.defaultModelName,
  });

  await Bun.write(CONFIG.pidFile, pid.toString());
  await updateState({
    text: "Starting...",
    isRecording: true,
    mode: "live",
    startTime: Date.now(),
  });

  const exitHandler = async () => {
    await log("INFO", "Daemon stopping");
    await cleanup();
    process.exit(0);
  };
  process.on("SIGINT", exitHandler);
  process.on("SIGTERM", exitHandler);

  const modelArg = getArg("--model");
  const noOverlay = args.includes("--no-overlay");
  const noType = args.includes("--no-type");

  const whisperBin = await findWhisperBinary();
  if (!whisperBin) {
    const msg =
      "whisper-stream not found. Add whisper-cpp to environment.systemPackages (not runtimeInputs)";
    await log("ERROR", msg);
    await updateState({
      text: "❌ whisper-cpp missing",
      isRecording: false,
      mode: "error",
      error: msg,
    });
    console.error(`Error: ${msg}`);
    await Bun.sleep(3000);
    process.exit(1);
  }

  const device = await ensureDeviceSelected();
  if (!device) {
    const msg = "No input device selected";
    await log("ERROR", msg);
    await updateState({
      text: "❌ No device",
      isRecording: false,
      mode: "error",
      error: msg,
    });
    await Bun.sleep(3000);
    process.exit(1);
  }
  await log("INFO", "Using input device", {
    device: device.name,
    sdlId: device.sdlId,
  });

  let modelPath: string;
  try {
    modelPath = await resolveModel(modelArg);
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    await log("ERROR", "Model error", { error: msg });
    await updateState({
      text: "❌ Model error",
      isRecording: false,
      mode: "error",
      error: msg,
    });
    await Bun.sleep(3000);
    process.exit(1);
  }

  if (!noOverlay) await startOverlay();

  await runWhisperStream(
    whisperBin,
    modelPath,
    noType,
    device.sdlId,
    device.name
  );
}

async function handleStatus() {
  try {
    const pid = await getRunningPid();
    let state: State = { text: "", isRecording: false, mode: "idle" };

    const file = Bun.file(CONFIG.stateFile);
    if (await file.exists()) {
      try {
        state = await file.json();
      } catch {}
    }

    console.log(
      JSON.stringify({
        active: pid !== null && state.isRecording,
        text: state.text || "",
        mode: state.mode,
        error: state.error,
        progress: state.progress,
        volume: state.volume,
        uptime: state.startTime
          ? Math.floor((Date.now() - state.startTime) / 1000)
          : 0,
      })
    );
  } catch (e) {
    console.log(
      JSON.stringify({
        active: false,
        text: "",
        mode: "error",
        error: String(e),
      })
    );
  }
}

async function handleSource() {
  try {
    const file = Bun.file(CONFIG.stateFile);
    if (!(await file.exists())) {
      console.log(
        JSON.stringify({ text: "Ready", class: "stopped", alt: "stopped" })
      );
      return;
    }

    const content = await file.text();
    if (!content.trim()) {
      console.log(
        JSON.stringify({ text: "Ready", class: "stopped", alt: "stopped" })
      );
      return;
    }

    const state = JSON.parse(content) as State;
    const volBar =
      state.volume !== undefined ? getVolumeIndicator(state.volume) : "";

    console.log(
      JSON.stringify({
        text: state.text ? `${volBar} ${state.text}`.trim() : volBar || "...",
        tooltip: buildTooltip(state),
        class: state.isRecording
          ? "playing"
          : state.mode === "error"
          ? "error"
          : "stopped",
        alt: state.isRecording ? "playing" : "stopped",
      })
    );
  } catch (e) {
    await log("ERROR", "handleSource failed", { error: String(e) });
    console.log(
      JSON.stringify({ text: "...", class: "stopped", alt: "stopped" })
    );
  }
}

function getVolumeIndicator(vol: number): string {
  smoothedVolume = smoothedVolume * 0.6 + vol * 0.4;
  const level = Math.round(smoothedVolume * 4);
  const bars = ["▁", "▂", "▃", "▅", "▇"];
  return bars[Math.min(level, 4)]!;
}

async function handleSelectDevice() {
  const devices = await getAudioDevices();
  if (devices.length === 0) {
    console.error("No audio input devices found");
    process.exit(1);
  }

  const config = await loadUserConfig();
  const selected = await selectDeviceWithRofi(devices, config.inputDevice);

  if (selected) {
    config.inputDevice = selected.name;
    await saveUserConfig(config);
    console.log(`Selected: ${selected.name}`);
  } else {
    console.log("No device selected");
  }
}

async function getAudioDevices(): Promise<AudioDevice[]> {
  try {
    const whisperBin = await findWhisperBinary();
    if (!whisperBin) return [];

    const proc = Bun.spawn([whisperBin, "-m", "/dev/null"], {
      stdout: "pipe",
      stderr: "pipe",
      env: { ...process.env, SDL_AUDIODRIVER: "pulseaudio" },
    });

    const stderr = await new Response(proc.stderr).text();
    await proc.exited;

    const devices: AudioDevice[] = [];
    const regex = /Capture device #(\d+): '([^']+)'/g;
    let match;
    while ((match = regex.exec(stderr)) !== null) {
      devices.push({ sdlId: parseInt(match[1]!), name: match[2]! });
    }

    return devices;
  } catch (e) {
    await log("ERROR", "Failed to get audio devices", { error: String(e) });
    return [];
  }
}

async function selectDeviceWithRofi(
  devices: AudioDevice[],
  currentName?: string
): Promise<AudioDevice | null> {
  if (devices.length === 0) return null;

  const lines = devices.map((d) => {
    const current = d.name === currentName ? " [current]" : "";
    return `${d.name}${current}`;
  });

  try {
    const result =
      await $`printf '%s\n' ${lines} | qs-dmenu -p "Input Device"`
        .nothrow()
        .quiet();
    if (result.exitCode !== 0 || !result.text().trim()) return null;

    const selectedLine = result
      .text()
      .trim()
      .replace(/ \[current\]$/, "");
    return devices.find((d) => d.name === selectedLine) || null;
  } catch (e) {
    await log("ERROR", "Rofi selection failed", { error: String(e) });
    return null;
  }
}

async function loadUserConfig(): Promise<UserConfig> {
  try {
    const file = Bun.file(CONFIG.configFile);
    if (await file.exists()) {
      return await file.json();
    }
  } catch {}
  return {};
}

async function saveUserConfig(config: UserConfig): Promise<void> {
  try {
    await mkdir(CONFIG.configDir, { recursive: true });
    await Bun.write(CONFIG.configFile, JSON.stringify(config, null, 2));
  } catch (e) {
    await log("ERROR", "Failed to save config", { error: String(e) });
  }
}

async function ensureDeviceSelected(): Promise<AudioDevice | null> {
  const config = await loadUserConfig();
  const devices = await getAudioDevices();

  if (devices.length === 0) {
    await log("ERROR", "No audio input devices available");
    return null;
  }

  if (config.inputDevice) {
    const device = devices.find((d) => d.name === config.inputDevice);
    if (device) return device;
    await log("WARN", "Configured device no longer exists", {
      device: config.inputDevice,
    });
  }

  if (devices.length === 1) {
    config.inputDevice = devices[0]!.name;
    await saveUserConfig(config);
    await log("INFO", "Auto-selected only available device", {
      device: devices[0]!.name,
    });
    return devices[0]!;
  }

  const selected = await selectDeviceWithRofi(devices);
  if (selected) {
    config.inputDevice = selected.name;
    await saveUserConfig(config);
    return selected;
  }

  return null;
}

async function handleTranscribe() {
  const inputFile = args[1];
  if (!inputFile || !existsSync(inputFile)) {
    console.error(
      inputFile
        ? `File not found: ${inputFile}`
        : "Usage: dictation transcribe <file>"
    );
    process.exit(1);
  }

  const ext = extname(inputFile).toLowerCase();
  const isVideo = CONFIG.supportedVideo.includes(
    ext as (typeof CONFIG.supportedVideo)[number]
  );
  const isAudio = CONFIG.supportedAudio.includes(
    ext as (typeof CONFIG.supportedAudio)[number]
  );

  if (!isVideo && !isAudio) {
    console.error(`Unsupported format: ${ext}`);
    process.exit(1);
  }

  const modelArg = getArg("--model");
  const outputFormat = (getArg("--format") || "srt") as SubtitleFormat;
  const outputFile = getArg("--output");
  const embedSubs = args.includes("--embed");

  await log("INFO", "Transcription started", {
    file: inputFile,
    format: outputFormat,
  });
  await updateState({
    text: `📝 ${basename(inputFile)}`,
    isRecording: true,
    mode: "transcribe",
    file: inputFile,
    startTime: Date.now(),
  });

  try {
    const wavFile = await prepareAudioFile(inputFile);
    const modelPath = await resolveModel(modelArg);
    const segments = await transcribeFile(wavFile, modelPath);
    const content = formatSubtitles(segments, outputFormat);
    const outPath = outputFile || inputFile.replace(ext, `.${outputFormat}`);

    await Bun.write(outPath, content);
    await log("INFO", "Transcription complete", {
      output: outPath,
      segments: segments.length,
    });

    if (embedSubs && isVideo) {
      await embedSubtitles(inputFile, outPath);
    }

    if (wavFile !== inputFile && existsSync(wavFile)) {
      try {
        await unlink(wavFile);
      } catch {}
    }

    await updateState({
      text: `✓ ${basename(outPath)}`,
      isRecording: false,
      mode: "idle",
      progress: "100%",
    });
    console.log(`Done: ${outPath}`);

    if (segments.length > 0) {
      console.log("\nTranscript:");
      segments.forEach((s) =>
        console.log(
          `[${formatTimestamp(s.start)} -> ${formatTimestamp(s.end)}] ${s.text}`
        )
      );
    }
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    await log("ERROR", "Transcription failed", { error: msg });
    await updateState({
      text: "❌ Failed",
      isRecording: false,
      mode: "error",
      error: msg,
    });
    console.error(msg);
    process.exit(1);
  }
}

function formatTimestamp(seconds: number): string {
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return `${m}:${s.toString().padStart(2, "0")}`;
}

async function getPulseSource(deviceName: string): Promise<string | null> {
  try {
    const status = await $`wpctl status`.text();
    const lines = status.split("\n");
    let inSources = false;
    let foundId: string | null = null;

    for (const line of lines) {
      if (line.includes("Sources:")) {
        inSources = true;
        continue;
      }
      if (
        inSources &&
        (line.includes("Filters:") ||
          line.includes("Streams:") ||
          line.includes("Sinks:") ||
          line.trim() === "")
      ) {
        if (line.trim() !== "") inSources = false;
      }

      if (inSources && line.includes(deviceName)) {
        const match = line.match(/(\d+)\./);
        if (match) {
          foundId = match[1]!;
          break;
        }
      }
    }

    if (!foundId) return null;

    const inspect = await $`wpctl inspect ${foundId}`.text();
    const nameMatch = inspect.match(/node\.name\s*=\s*"([^"]+)"/);

    return nameMatch ? nameMatch[1]! : null;
  } catch (e) {
    return null;
  }
}

async function runWhisperStream(
  bin: string,
  modelPath: string,
  noType: boolean,
  deviceId: number,
  deviceName?: string
) {
  const modelName = basename(modelPath)
    .replace("ggml-", "")
    .replace(".bin", "");
  await log("INFO", "Starting whisper-stream", { model: modelName, deviceId });

  let env: Record<string, string | undefined> = {
    ...process.env,
    SDL_AUDIODRIVER: "pulseaudio",
  };

  if (deviceName) {
    const pulseSource = await getPulseSource(deviceName);
    if (pulseSource) {
      await log("INFO", "Forcing PulseAudio source", { source: pulseSource });
      // PULSE_SOURCE forces the 'default' device in the PA client to match this source
      env = { ...env, PULSE_SOURCE: pulseSource };
    } else {
      await log("WARN", "Could not resolve PulseAudio source name", {
        deviceName,
      });
    }
  }

  await updateState({
    text: `Loading ${modelName}...`,
    isRecording: true,
    mode: "live",
  });

  let initialized = false;
  const watchdog = setTimeout(async () => {
    if (!initialized) {
      await log("ERROR", "Init timeout - no audio device response in 60s");
      await updateState({
        text: "❌ Timeout",
        isRecording: false,
        mode: "error",
        error: "Init timeout",
      });
      process.exit(1);
    }
  }, 60000);

  const proc = Bun.spawn(
    [
      bin,
      "-m",
      modelPath,
      "-t",
      "4",
      "--step",
      "500",
      "--length",
      "5000",
      "-vth",
      "0.5",
      "-c",
      "0", // Force default device, as PULSE_SOURCE handles selection
    ],
    {
      stdio: ["ignore", "pipe", "pipe"],
      env,
    }
  );

  let lastText = "";
  let typedText = ""; // Track what we've actually typed for incremental updates
  let lastUpdateTime = Date.now();

  const stripAnsi = (s: string) => s.replace(/\x1b\[[0-9;]*[a-zA-Z]/g, "");

  const isValidTranscript = (text: string): boolean => {
    if (!text || text.length < 2) return false;

    // Filter parenthetical noise: (music), (beeping), [inaudible], etc.
    // We allow brackets generally, but block common hallucination patterns
    if (/^[\[\(].*[\]\)]$/.test(text)) {
      const inner = text.slice(1, -1).trim().toLowerCase();
      // Block timestamps [00:12]
      if (/^[\d:.]+$/.test(inner)) return false;
      
      const noiseTriggers = [
        "music", "applause", "inaudible", "silence", "noise", "beeping",
        "laughter", "sound", "foreign", "background", "chatter",
        "end of recording", "video", "audio", "transcript", "subtitle",
        "subtitles", "copyright", "caption", "notes", "no audio"
      ];
      
      // If the bracketed text starts with or equals a noise trigger, block it
      if (noiseTriggers.some(t => inner === t || inner.startsWith(t + " "))) {
        return false;
      }
    }

    if (/^\*.*\*$/.test(text)) return false;

    // Common Hallucinations
    if (/^Amps\s*=\s*0/i.test(text)) return false;
    if (/^Subtitles? by/i.test(text)) return false;
    if (/^[0-9]+$/.test(text)) return false; // Just numbers

    // URL Hallucinations
    if (/\.com|\.org|\.net|\.io/i.test(text) && !text.includes(" "))
      return false;

    const dominated = [
      "init:",
      "whisper_",
      "load_backend",
      "ggml_",
      "main:",
      "system_info",
      "Device",
      "sample rate",
      "format:",
      "channels:",
      "samples per frame",
      "processing",
      "n_new_line",
      "timings",
      "fallbacks",
      "mel time",
      "encode time",
      "decode time",
      "batchd time",
      "prompt time",
      "total time",
      "compute buffer",
      "kv ",
      "model size",
      "adding",
      "n_vocab",
      "n_audio",
      "n_text",
      "n_mels",
      "ftype",
      "qntvr",
      "type",
      "n_langs",
      "CUDA",
      "backends",
      "gpu",
      "flash attn",
      "dtw",
      "devices",
      "loading model",
      "capture device",
      "attempt to open",
      "obtained spec",
      "[Start speaking]",
    ];
    for (const d of dominated) {
      if (text.includes(d)) return false;
    }
    return true;
  };

  const processChunk = async (chunk: string) => {
    const cleaned = stripAnsi(chunk);
    const parts = cleaned.split(/[\r\n]+/);

    for (const part of parts) {
      // Ensure no newlines (safeguard) and trim
      const text = part.replace(/[\r\n]+/g, " ").trim();
      if (!text) continue;

      if (text.includes("Capture device #")) {
        const match = text.match(/Capture device #\d+: '([^']+)'/);
        if (match) await log("INFO", "Audio device", { name: match[1] });
      }

      if (text.includes("attempt to open default capture")) {
        await log("INFO", "Opening mic");
        await updateState({
          text: "Opening mic...",
          isRecording: true,
          mode: "live",
        });
      }

      if (text.includes("obtained spec for input device")) {
        await log("INFO", "Mic ready");
      }

      if (text.includes("processing") && text.includes("samples")) {
        if (!initialized) {
          initialized = true;
          clearTimeout(watchdog);
          await log("INFO", "Streaming active");
        }
        await updateState({
          text: "🎤 Listening...",
          isRecording: true,
          mode: "live",
          volume: 0.2,
        });
      }

      if (text.includes("found 0 capture")) {
        await log("ERROR", "No mic found");
        await updateState({
          text: "❌ No mic",
          isRecording: false,
          mode: "error",
          error: "No mic",
        });
        proc.kill();
        process.exit(1);
      }

      if (isValidTranscript(text) && text !== lastText) {
        lastText = text;
        const now = Date.now();

        if (now - lastUpdateTime > 100) {
          lastUpdateTime = now;
          await log("INFO", "Transcribed", { text: text.slice(0, 60) });

          if (!noType) {
            try {
              if (text.startsWith(typedText)) {
                const delta = text.slice(typedText.length);
                if (delta) {
                  await $`wtype -- ${delta}`.quiet();
                  typedText = text;
                }
              } else {
                let commonLen = 0;
                const minLen = Math.min(typedText.length, text.length);
                while (
                  commonLen < minLen &&
                  typedText[commonLen] === text[commonLen]
                ) {
                  commonLen++;
                }

                const backspaces = typedText.length - commonLen;

                if (backspaces > 50 || commonLen < 3) {
                  // New segment from whisper - append with space, reset tracking
                  const separator = typedText.length > 0 ? " " : "";
                  await $`wtype -- ${separator}${text}`.quiet();
                  typedText = text;
                } else {
                  // Small correction - backspace and fix
                  const newText = text.slice(commonLen);
                  for (let i = 0; i < backspaces; i++) {
                    await $`wtype -k BackSpace`.quiet();
                  }
                  if (newText) {
                    await $`wtype -- ${newText}`.quiet();
                  }
                  typedText = text;
                }
              }
            } catch (e) {
              await log("WARN", "wtype failed", { error: String(e) });
            }
          }

          const displayText =
            text.length > 50 ? text.slice(0, 47) + "..." : text;
          await updateState({
            text: displayText,
            isRecording: true,
            mode: "live",
            volume: 0.8,
          });
        }
      }
    }
  };

  const readStream = async (stream: ReadableStream, name: string) => {
    const reader = stream.getReader();
    const decoder = new TextDecoder();
    let buffer = "";

    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        buffer += decoder.decode(value, { stream: true });
        await processChunk(buffer);
        buffer = "";
      }
      if (buffer.trim()) await processChunk(buffer);
    } catch (e) {
      await log("ERROR", `Stream error (${name})`, { error: String(e) });
    }
  };

  await log("INFO", "Spawned whisper-stream process", { pid: proc.pid });

  await Promise.all([
    readStream(proc.stdout, "stdout"),
    readStream(proc.stderr, "stderr"),
    proc.exited,
  ]);

  clearTimeout(watchdog);
  const exitCode = await proc.exited;
  await log("INFO", "whisper-stream exited", { exitCode });
  await updateState({ text: "Stopped", isRecording: false, mode: "idle" });
}

async function prepareAudioFile(inputFile: string): Promise<string> {
  const outputWav = join(tmpdir(), `dictation-${Date.now()}.wav`);
  await log("INFO", "Converting to WAV", { input: basename(inputFile) });
  await updateState({
    text: "Converting...",
    isRecording: true,
    mode: "transcribe",
    progress: "5%",
  });

  try {
    await $`ffmpeg -y -i ${inputFile} -ar 16000 -ac 1 -c:a pcm_s16le ${outputWav}`.quiet();
    return outputWav;
  } catch (e) {
    throw new Error(`Conversion failed: ${e}`);
  }
}

async function transcribeFile(
  wavFile: string,
  modelPath: string
): Promise<TranscriptSegment[]> {
  await log("INFO", "Transcribing file", { file: basename(wavFile) });
  await updateState({
    text: "Transcribing...",
    isRecording: true,
    mode: "transcribe",
    progress: "20%",
  });

  try {
    const result =
      await $`whisper-cli -m ${modelPath} -f ${wavFile} -pp`.text();
    const segments: TranscriptSegment[] = [];

    for (const line of result.split("\n")) {
      const match = line.match(
        /\[(\d{2}):(\d{2}):(\d{2})\.(\d{3})\s*-->\s*(\d{2}):(\d{2}):(\d{2})\.(\d{3})\]\s*(.*)/
      );
      if (match) {
        const start =
          parseInt(match[1]!) * 3600 +
          parseInt(match[2]!) * 60 +
          parseInt(match[3]!) +
          parseInt(match[4]!) / 1000;
        const end =
          parseInt(match[5]!) * 3600 +
          parseInt(match[6]!) * 60 +
          parseInt(match[7]!) +
          parseInt(match[8]!) / 1000;
        const text = match[9]!.trim();
        if (text && !text.startsWith("[") && !text.startsWith("(")) {
          segments.push({ start, end, text });
        }
      }
    }

    await log("INFO", "Parsed segments", { count: segments.length });
    await updateState({
      text: "Processing...",
      isRecording: true,
      mode: "transcribe",
      progress: "90%",
    });
    return segments;
  } catch (e) {
    throw new Error(`Transcription failed: ${e}`);
  }
}

function formatSubtitles(
  segments: TranscriptSegment[],
  format: SubtitleFormat
): string {
  const fmt = (s: number, dot = false) => {
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    const sec = Math.floor(s % 60);
    const ms = Math.floor((s % 1) * 1000);
    return `${h.toString().padStart(2, "0")}:${m
      .toString()
      .padStart(2, "0")}:${sec.toString().padStart(2, "0")}${
      dot ? "." : ","
    }${ms.toString().padStart(3, "0")}`;
  };

  if (format === "vtt") {
    return (
      "WEBVTT\n\n" +
      segments
        .map(
          (s) => `${fmt(s.start, true)} --> ${fmt(s.end, true)}\n${s.text}\n`
        )
        .join("\n")
    );
  }
  if (format === "txt") {
    return segments.map((s) => s.text).join("\n");
  }
  return segments
    .map((s, i) => `${i + 1}\n${fmt(s.start)} --> ${fmt(s.end)}\n${s.text}\n`)
    .join("\n");
}

async function embedSubtitles(
  videoFile: string,
  subtitleFile: string
): Promise<void> {
  const ext = extname(videoFile);
  const output = videoFile.replace(ext, `.subtitled${ext}`);
  await log("INFO", "Embedding subtitles", { output: basename(output) });
  await updateState({
    text: "Embedding...",
    isRecording: true,
    mode: "transcribe",
    progress: "95%",
  });

  try {
    if (ext === ".mkv") {
      await $`ffmpeg -y -i ${videoFile} -i ${subtitleFile} -c copy -c:s srt ${output}`.quiet();
    } else {
      await $`ffmpeg -y -i ${videoFile} -vf subtitles=${subtitleFile} -c:a copy ${output}`.quiet();
    }
  } catch (e) {
    throw new Error(`Embedding failed: ${e}`);
  }
}

async function startOverlay() {
  await updateState({
    text: "Starting overlay...",
    isRecording: true,
    mode: "live",
  });

  try {
    const cmd = `${process.argv[0]} ${process.argv[1]} source`;
    const env = {
      ...process.env,
      OVERLAY_COMMAND: cmd,
      LYRICS_POSITION: getArg("--position") || "top",
      LYRICS_LINES: getArg("--lines") || "2",
      LYRICS_FONT_SIZE: getArg("--font-size") || "32",
      LYRICS_COLOR: getArg("--color") || "#ffffff",
      LYRICS_OPACITY: getArg("--opacity") || "0.95",
      LYRICS_UPDATE_INTERVAL: getArg("--interval") || "100",
      LYRICS_SHADOW: "true",
    };

    Bun.spawn(["toggle-lyrics-overlay", "show"], {
      env,
      stdio: ["ignore", "ignore", "ignore"],
      detached: true,
    }).unref();
    await log("INFO", "Overlay started");
  } catch (e) {
    await log("WARN", "Overlay spawn failed", { error: String(e) });
  }
}

async function findWhisperBinary(): Promise<string | null> {
  try {
    await $`which whisper-stream`.quiet();
    return "whisper-stream";
  } catch {
    return null;
  }
}

async function resolveModel(input: string | null): Promise<string> {
  const name = input || CONFIG.defaultModelName;
  if (name.includes("/")) {
    if (existsSync(name)) return name;
    throw new Error(`Model not found: ${name}`);
  }
  return await ensureModelDownloaded(name);
}

async function ensureModelDownloaded(modelName: string): Promise<string> {
  const filename = `ggml-${modelName}.bin`;
  const path = join(CONFIG.userModelDir, filename);

  if (existsSync(path)) {
    await log("INFO", "Using cached model", { model: modelName });
    return path;
  }

  await log("INFO", "Downloading model", { model: modelName });
  await updateState({
    text: `⬇️ Downloading ${modelName}...`,
    isRecording: true,
    mode: "downloading",
    progress: "0%",
  });

  try {
    await $`which whisper-cpp-download-ggml-model`.quiet();
  } catch {
    throw new Error("whisper-cpp-download-ggml-model not found");
  }

  await mkdir(CONFIG.userModelDir, { recursive: true });

  const proc = Bun.spawn(
    [
      "sh",
      "-c",
      `cd "${CONFIG.userModelDir}" && whisper-cpp-download-ggml-model "${modelName}" 2>&1`,
    ],
    { stdio: ["ignore", "pipe", "pipe"] }
  );

  const reader = proc.stdout.getReader();
  const decoder = new TextDecoder();
  let lastProgress = "";

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      const text = decoder.decode(value);
      const match = text.match(/(\d+)%/);
      if (match && match[1] !== lastProgress) {
        lastProgress = match[1]!;
        await updateState({
          text: `⬇️ ${modelName} ${lastProgress}%`,
          isRecording: true,
          mode: "downloading",
          progress: `${lastProgress}%`,
        });
      }
    }
  } catch {}

  await proc.exited;

  if (existsSync(path)) {
    await log("INFO", "Model download complete", { model: modelName });
    return path;
  }
  throw new Error(`Download failed for ${modelName}`);
}

async function getRunningPid(): Promise<number | null> {
  const file = Bun.file(CONFIG.pidFile);
  if (await file.exists()) {
    try {
      const pid = parseInt(await file.text());
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
    let state: State = { text: "", isRecording: false, mode: "idle" };
    const file = Bun.file(CONFIG.stateFile);
    if (await file.exists()) {
      try {
        state = await file.json();
      } catch {}
    }
    await Bun.write(
      CONFIG.stateFile,
      JSON.stringify({ ...state, ...newState })
    );
  } catch {}
}

async function cleanup() {
  try {
    await $`toggle-lyrics-overlay hide`.quiet().catch(() => {});
    if (existsSync(CONFIG.pidFile)) await unlink(CONFIG.pidFile);
    if (existsSync(CONFIG.stateFile)) await unlink(CONFIG.stateFile);
  } catch {}
}

function getArg(flag: string): string | null {
  const i = args.indexOf(flag);
  return i !== -1 && i + 1 < args.length ? args[i + 1]! : null;
}

function buildTooltip(state: State): string {
  const lines: string[] = [];
  const modeLabels = {
    live: "🎙️ Live",
    transcribe: "📝 Transcribe",
    downloading: "⬇️ Downloading",
    error: "❌ Error",
    idle: "⏸️ Idle",
  };
  lines.push(`<b>${modeLabels[state.mode] || state.mode}</b>`);

  if (state.file) lines.push(`File: ${basename(state.file)}`);
  if (state.progress) lines.push(`Progress: ${state.progress}`);
  if (state.startTime) {
    const s = Math.floor((Date.now() - state.startTime) / 1000);
    lines.push(
      `Time: ${Math.floor(s / 60)}:${(s % 60).toString().padStart(2, "0")}`
    );
  }
  if (state.error) lines.push(`<span color='#ff6b6b'>${state.error}</span>`);
  lines.push("", `<b>► ${state.text}</b>`);
  return lines.join("\n");
}

function printHelp() {
  console.log(`
Dictation - Speech-to-text using whisper-cpp

Host: ${HOST} (default model: ${CONFIG.defaultModelName})

COMMANDS:
  toggle              Start/Stop live dictation
  select-device       Select input device via rofi
  run                 Run daemon (internal)
  status              JSON status for waybar
  source              JSON for overlay (internal)
  transcribe <file>   Transcribe media file
  help                Show this help

LIVE OPTIONS:
  --model <name>      Model: tiny, base, small, medium, large (default: ${CONFIG.defaultModelName})
  --no-overlay        Disable overlay
  --no-type           Don't type recognized text
  --position <pos>    Overlay: top, bottom, center
  --font-size <n>     Font size (default: 32)

TRANSCRIBE OPTIONS:
  --format <fmt>      srt, vtt, txt (default: srt)
  --output <file>     Output path
  --embed             Embed subtitles in video

EXAMPLES:
  dictation toggle
  dictation select-device
  dictation toggle --model base.en --position bottom
  dictation transcribe video.mp4 --embed
  dictation transcribe audio.mp3 --format txt

CONFIG: ${CONFIG.configFile}
LOGS: ${CONFIG.logFile}
`);
}
