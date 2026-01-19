#!/usr/bin/env bun
/**
 * dictation.ts - Realtime dictation and media transcription using whisper-cpp
 *
 * Features:
 * - Live microphone dictation with wtype output
 * - Media file transcription (mp3, wav, mp4, etc.)
 * - Subtitle generation (SRT/VTT) with optional ffmpeg embedding
 * - Visual overlay via lyrics-overlay with customizable options
 * - Structured JSON status output for waybar integration
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
import { existsSync, unlinkSync, mkdirSync, statSync } from "node:fs";

// --- Configuration ---
const CONFIG = {
  pidFile: join(tmpdir(), "dictation.pid"),
  stateFile: join(tmpdir(), "dictation-state.json"),
  logFile: join(tmpdir(), "dictation.log"),
  defaultModelName: "medium.en",
  userModelDir: join(homedir(), ".cache", "whisper"),
  // Supported media extensions for transcription
  supportedAudio: [".mp3", ".wav", ".flac", ".ogg", ".m4a", ".aac", ".wma"],
  supportedVideo: [".mp4", ".mkv", ".avi", ".mov", ".webm", ".wmv", ".flv"],
} as const;

// --- Types ---
interface State {
  text: string;
  isRecording: boolean;
  mode: "idle" | "live" | "transcribe" | "error";
  error?: string;
  progress?: string;
  file?: string;
  startTime?: number;
}

interface TranscriptSegment {
  start: number; // seconds
  end: number; // seconds
  text: string;
}

type SubtitleFormat = "srt" | "vtt" | "txt";

// --- Logging ---
function log(level: "INFO" | "WARN" | "ERROR" | "DEBUG", message: string, data?: unknown) {
  const timestamp = new Date().toISOString();
  const logLine = `[${timestamp}] [${level}] ${message}${data ? ` ${JSON.stringify(data)}` : ""}`;
  console.error(logLine); // stderr for daemon logs

  // Also append to log file for persistent debugging
  try {
    const file = Bun.file(CONFIG.logFile);
    const existing = existsSync(CONFIG.logFile) ? Bun.file(CONFIG.logFile).text() : "";
    Bun.write(CONFIG.logFile, existing + logLine + "\n");
  } catch {
    // Ignore log file errors
  }
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
    await handleStatus();
    break;
  case "source":
    await handleSource();
    break;
  case "transcribe":
    await handleTranscribe();
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
    log("INFO", "Stopping dictation daemon", { pid });
    try {
      process.kill(pid, "SIGTERM");
    } catch {
      // Process might be dead already
    }
    await cleanup();
    console.log("Dictation stopped.");
  } else {
    log("INFO", "Starting dictation daemon");

    // Spawn the daemon in background
    const logOut = Bun.file("/tmp/dictation.out.log");
    const logErr = Bun.file("/tmp/dictation.err.log");

    const proc = Bun.spawn([process.argv[0]!, process.argv[1]!, "run", ...args.slice(1)], {
      stdio: ["ignore", logOut, logErr],
      detached: true,
      env: { ...process.env },
    });
    proc.unref();

    // Wait for PID to appear (up to 3 seconds)
    let checks = 0;
    while (checks < 30) {
      await Bun.sleep(100);
      if (await getRunningPid()) {
        console.log("Dictation started.");
        return;
      }
      checks++;
    }
    console.error("Failed to start dictation daemon (timeout). Check /tmp/dictation.err.log");
    process.exit(1);
  }
}

async function handleRun() {
  const pid = process.pid;
  log("INFO", "Daemon starting", { pid });

  try {
    await Bun.write(CONFIG.pidFile, pid.toString());
  } catch (e) {
    log("ERROR", "Failed to write PID file", e);
    process.exit(1);
  }

  // Initialize state
  await updateState({
    text: "Initializing...",
    isRecording: true,
    mode: "live",
    startTime: Date.now(),
  });

  // Cleanup on exit
  const exitHandler = async () => {
    log("INFO", "Daemon shutting down");
    await cleanup();
    process.exit(0);
  };
  process.on("SIGINT", exitHandler);
  process.on("SIGTERM", exitHandler);

  // Parse options
  const modelArg = getArg("--model");
  const noOverlay = args.includes("--no-overlay");
  const noType = args.includes("--no-type");

  // Check dependencies
  const whisperBin = await findWhisperBinary();
  if (!whisperBin) {
    const errorMsg = "whisper-stream not found in PATH";
    log("ERROR", errorMsg);
    await updateState({
      text: "Missing: whisper-stream",
      isRecording: false,
      mode: "error",
      error: errorMsg,
    });
    await Bun.sleep(3000);
    process.exit(1);
  }
  log("INFO", "Found whisper binary", { path: whisperBin });

  // Resolve Model Path
  let modelPath = "";
  try {
    modelPath = await resolveModel(modelArg);
    log("INFO", "Using model", { path: modelPath });
  } catch (e: unknown) {
    const errorMsg = e instanceof Error ? e.message : String(e);
    log("ERROR", "Model resolution failed", { error: errorMsg });
    await updateState({
      text: "Model Error",
      isRecording: false,
      mode: "error",
      error: errorMsg,
    });
    await Bun.sleep(3000);
    process.exit(1);
  }

  // Start Overlay
  if (!noOverlay) {
    await startOverlay();
  }

  // Run whisper-stream
  await runWhisperStream(whisperBin, modelPath, noType);
}

async function handleStatus() {
  // Output JSON status for waybar integration
  try {
    const pid = await getRunningPid();
    const file = Bun.file(CONFIG.stateFile);
    let state: State = { text: "", isRecording: false, mode: "idle" };

    if (await file.exists()) {
      try {
        state = await file.json();
      } catch {
        // Invalid JSON, use defaults
      }
    }

    const output = {
      active: pid !== null && state.isRecording,
      text: state.text || (pid ? "Active" : ""),
      mode: state.mode,
      error: state.error,
      progress: state.progress,
      uptime: state.startTime ? Math.floor((Date.now() - state.startTime) / 1000) : 0,
    };

    console.log(JSON.stringify(output));
  } catch (e) {
    console.log(JSON.stringify({ active: false, text: "", mode: "error", error: String(e) }));
  }
}

async function handleSource() {
  // Output JSON for lyrics-overlay
  try {
    const file = Bun.file(CONFIG.stateFile);
    if (await file.exists()) {
      const state = (await file.json()) as State;

      // Format for lyrics-overlay.qml compatibility
      const modeIcon =
        state.mode === "live" ? "🎙️" : state.mode === "transcribe" ? "📝" : state.mode === "error" ? "❌" : "⏸️";

      const output = {
        text: state.text || "...",
        tooltip: buildTooltip(state),
        class: state.isRecording ? "playing" : state.mode === "error" ? "error" : "stopped",
        alt: state.isRecording ? "playing" : "stopped",
      };

      console.log(JSON.stringify(output));
    } else {
      console.log(JSON.stringify({ text: "Dictation Ready", class: "stopped", alt: "stopped" }));
    }
  } catch {
    console.log(JSON.stringify({ text: "Error", class: "error", alt: "error" }));
  }
}

async function handleTranscribe() {
  const inputFile = args[1];
  if (!inputFile) {
    console.error("Error: No input file specified");
    console.error("Usage: dictation transcribe <file> [options]");
    process.exit(1);
  }

  if (!existsSync(inputFile)) {
    console.error(`Error: File not found: ${inputFile}`);
    process.exit(1);
  }

  const ext = extname(inputFile).toLowerCase();
  const isVideo = CONFIG.supportedVideo.includes(ext);
  const isAudio = CONFIG.supportedAudio.includes(ext);

  if (!isVideo && !isAudio) {
    console.error(`Error: Unsupported file format: ${ext}`);
    console.error(`Supported: ${[...CONFIG.supportedAudio, ...CONFIG.supportedVideo].join(", ")}`);
    process.exit(1);
  }

  // Parse transcribe options
  const modelArg = getArg("--model");
  const outputFormat = (getArg("--format") || "srt") as SubtitleFormat;
  const outputFile = getArg("--output");
  const embedSubs = args.includes("--embed");
  const language = getArg("--language") || "en";

  log("INFO", "Starting transcription", { inputFile, format: outputFormat, embed: embedSubs });

  await updateState({
    text: `Transcribing: ${basename(inputFile)}`,
    isRecording: true,
    mode: "transcribe",
    file: inputFile,
    startTime: Date.now(),
  });

  try {
    // Convert to WAV if needed (whisper-cpp works best with 16kHz mono WAV)
    const wavFile = await prepareAudioFile(inputFile, isVideo);

    // Resolve model
    const modelPath = await resolveModel(modelArg);

    // Run transcription
    const segments = await transcribeFile(wavFile, modelPath, language);

    // Generate output
    const subtitleContent = formatSubtitles(segments, outputFormat);

    // Determine output path
    const outPath = outputFile || inputFile.replace(ext, `.${outputFormat}`);
    await Bun.write(outPath, subtitleContent);
    log("INFO", "Subtitles written", { path: outPath });

    // Embed subtitles if requested (for video files)
    if (embedSubs && isVideo) {
      await embedSubtitles(inputFile, outPath, outputFormat);
    }

    // Cleanup temp WAV if we created one
    if (wavFile !== inputFile && existsSync(wavFile)) {
      unlinkSync(wavFile);
    }

    await updateState({
      text: `Done: ${basename(outPath)}`,
      isRecording: false,
      mode: "idle",
      progress: "100%",
    });

    console.log(`Transcription complete: ${outPath}`);
    if (embedSubs && isVideo) {
      const embeddedFile = inputFile.replace(ext, `.subtitled${ext}`);
      console.log(`Subtitles embedded: ${embeddedFile}`);
    }
  } catch (e: unknown) {
    const errorMsg = e instanceof Error ? e.message : String(e);
    log("ERROR", "Transcription failed", { error: errorMsg });
    await updateState({
      text: "Transcription Failed",
      isRecording: false,
      mode: "error",
      error: errorMsg,
    });
    console.error(`Transcription failed: ${errorMsg}`);
    process.exit(1);
  }
}

// --- Whisper Stream Logic ---

async function runWhisperStream(whisperBin: string, modelPath: string, noType: boolean) {
  const modelName = basename(modelPath);
  log("INFO", "Loading model", { model: modelName });
  await updateState({ text: `Loading ${modelName}...`, isRecording: true, mode: "live" });

  // Watchdog timer - abort if init takes too long
  let watchdogCleared = false;
  const watchdog = setTimeout(async () => {
    if (!watchdogCleared) {
      log("ERROR", "Initialization timeout after 30s");
      await updateState({
        text: "Init Timeout",
        isRecording: false,
        mode: "error",
        error: "Timeout waiting for whisper-stream to initialize",
      });
      process.exit(1);
    }
  }, 30000);

  const proc = Bun.spawn(
    [whisperBin, "-m", modelPath, "-t", "4", "--step", "500", "--length", "5000", "-vth", "0.6"],
    { stdio: ["ignore", "pipe", "pipe"] }
  );

  // Track last recognized text for deduplication
  let lastText = "";
  let consecutiveEmptyCount = 0;

  const processLine = async (line: string, source: string) => {
    const trimmed = line.trim();
    if (!trimmed) return;

    log("DEBUG", `[${source}] ${trimmed}`);

    // Initialization state updates
    if (trimmed.includes("load_backend")) {
      await updateState({ text: "Loading backend...", isRecording: true, mode: "live" });
    } else if (trimmed.includes("init: attempt to open") || trimmed.includes("init: found")) {
      await updateState({ text: "Opening audio device...", isRecording: true, mode: "live" });
    } else if (trimmed.includes("whisper_model_load") || trimmed.includes("loading model")) {
      await updateState({ text: "Loading model weights...", isRecording: true, mode: "live" });
    } else if (trimmed.includes("whisper_init_state")) {
      await updateState({ text: "Initializing context...", isRecording: true, mode: "live" });
    } else if (
      trimmed.includes("computed_timestamps") ||
      trimmed.includes("[Start speaking]") ||
      trimmed.includes("main: processing")
    ) {
      if (!watchdogCleared) {
        clearTimeout(watchdog);
        watchdogCleared = true;
      }
      await updateState({ text: "🎤 Listening...", isRecording: true, mode: "live" });
    }

    // Error detection
    if (
      trimmed.includes("failed to open") ||
      trimmed.includes("failed to initialize") ||
      trimmed.includes("found 0 capture devices") ||
      trimmed.includes("error:")
    ) {
      log("ERROR", "Fatal error detected", { line: trimmed });
      await updateState({
        text: "Audio Error",
        isRecording: false,
        mode: "error",
        error: trimmed,
      });
      proc.kill();
      process.exit(1);
    }

    // Transcription output - matches [timestamp] text format
    const match = trimmed.match(/^\[.*?\]\s*(.*)/);
    if (match) {
      const text = match[1]!.trim();

      // Filter out empty, duplicate, or noise-only results
      if (!text || text === lastText || text === "[BLANK_AUDIO]" || text.match(/^\[.*\]$/)) {
        consecutiveEmptyCount++;
        if (consecutiveEmptyCount > 10) {
          await updateState({ text: "🎤 Listening...", isRecording: true, mode: "live" });
        }
        return;
      }

      consecutiveEmptyCount = 0;
      lastText = text;
      log("INFO", "Recognized", { text });

      // Type the text if enabled
      if (!noType) {
        try {
          await $`wtype ${text} `.quiet();
        } catch (e) {
          log("WARN", "wtype failed", e);
        }
      }

      await updateState({
        text: text.length > 60 ? text.slice(0, 57) + "..." : text,
        isRecording: true,
        mode: "live",
      });
    }
  };

  // Stream readers for stdout and stderr
  const readStream = async (stream: ReadableStream, name: string) => {
    const reader = stream.getReader();
    const decoder = new TextDecoder();
    let buffer = "";

    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        buffer += decoder.decode(value, { stream: true });
        const lines = buffer.split(/[\n\r]+/);
        buffer = lines.pop() || ""; // Keep incomplete line in buffer

        for (const line of lines) {
          await processLine(line, name);
        }
      }

      // Process any remaining buffer
      if (buffer.trim()) {
        await processLine(buffer, name);
      }
    } catch (e) {
      log("ERROR", `Stream read error (${name})`, e);
    }
  };

  // Run stream readers and wait for process exit
  await Promise.all([readStream(proc.stdout, "stdout"), readStream(proc.stderr, "stderr"), proc.exited]);

  clearTimeout(watchdog);
  log("INFO", "Whisper process exited");
  await updateState({ text: "Stopped", isRecording: false, mode: "idle" });
}

// --- File Transcription Logic ---

async function prepareAudioFile(inputFile: string, isVideo: boolean): Promise<string> {
  const ext = extname(inputFile).toLowerCase();

  // If already a compatible WAV, use directly
  if (ext === ".wav") {
    // Check if it's 16kHz mono (optimal for whisper)
    // For simplicity, we'll convert anyway to ensure compatibility
  }

  // Convert to 16kHz mono WAV using ffmpeg
  const outputWav = join(tmpdir(), `dictation-${Date.now()}.wav`);

  log("INFO", "Converting to WAV", { input: inputFile, output: outputWav });
  await updateState({ text: "Converting audio...", isRecording: true, mode: "transcribe", progress: "5%" });

  try {
    await $`ffmpeg -y -i ${inputFile} -ar 16000 -ac 1 -c:a pcm_s16le ${outputWav}`.quiet();
    return outputWav;
  } catch (e) {
    throw new Error(`Audio conversion failed: ${e}`);
  }
}

async function transcribeFile(wavFile: string, modelPath: string, language: string): Promise<TranscriptSegment[]> {
  log("INFO", "Starting whisper transcription", { file: wavFile, model: modelPath });
  await updateState({ text: "Transcribing...", isRecording: true, mode: "transcribe", progress: "10%" });

  // Use whisper-cpp CLI for file transcription (outputs to stdout)
  // whisper-cpp outputs timestamps in [HH:MM:SS.mmm --> HH:MM:SS.mmm] format
  try {
    const result = await $`whisper-cpp -m ${modelPath} -f ${wavFile} -l ${language} --output-txt --output-srt -pp`.text();

    // Parse the output - whisper-cpp with -pp prints progress and transcription
    const segments: TranscriptSegment[] = [];
    const lines = result.split("\n");

    // Parse SRT-style output from whisper-cpp
    let currentSegment: Partial<TranscriptSegment> = {};

    for (const line of lines) {
      // Match timestamp line: [00:00:00.000 --> 00:00:05.000]
      const timeMatch = line.match(/\[(\d{2}):(\d{2}):(\d{2})\.(\d{3})\s*-->\s*(\d{2}):(\d{2}):(\d{2})\.(\d{3})\]/);
      if (timeMatch) {
        const startSec =
          parseInt(timeMatch[1]!) * 3600 +
          parseInt(timeMatch[2]!) * 60 +
          parseInt(timeMatch[3]!) +
          parseInt(timeMatch[4]!) / 1000;
        const endSec =
          parseInt(timeMatch[5]!) * 3600 +
          parseInt(timeMatch[6]!) * 60 +
          parseInt(timeMatch[7]!) +
          parseInt(timeMatch[8]!) / 1000;

        currentSegment = { start: startSec, end: endSec };
        continue;
      }

      // Text line following timestamp
      const text = line.trim();
      if (text && currentSegment.start !== undefined) {
        segments.push({
          start: currentSegment.start,
          end: currentSegment.end || currentSegment.start + 5,
          text,
        });
        currentSegment = {};
      }
    }

    // Alternative: parse from generated .srt file if whisper-cpp created one
    const srtFile = wavFile.replace(".wav", ".srt");
    if (segments.length === 0 && existsSync(srtFile)) {
      const srtContent = await Bun.file(srtFile).text();
      return parseSrtFile(srtContent);
    }

    log("INFO", "Transcription complete", { segments: segments.length });
    await updateState({ text: "Processing...", isRecording: true, mode: "transcribe", progress: "90%" });

    return segments;
  } catch (e) {
    throw new Error(`Transcription failed: ${e}`);
  }
}

function parseSrtFile(content: string): TranscriptSegment[] {
  const segments: TranscriptSegment[] = [];
  const blocks = content.split(/\n\n+/);

  for (const block of blocks) {
    const lines = block.trim().split("\n");
    if (lines.length < 2) continue;

    // Parse timestamp line: 00:00:00,000 --> 00:00:05,000
    const timeMatch = lines[1]?.match(/(\d{2}):(\d{2}):(\d{2}),(\d{3})\s*-->\s*(\d{2}):(\d{2}):(\d{2}),(\d{3})/);
    if (!timeMatch) continue;

    const startSec =
      parseInt(timeMatch[1]!) * 3600 +
      parseInt(timeMatch[2]!) * 60 +
      parseInt(timeMatch[3]!) +
      parseInt(timeMatch[4]!) / 1000;
    const endSec =
      parseInt(timeMatch[5]!) * 3600 +
      parseInt(timeMatch[6]!) * 60 +
      parseInt(timeMatch[7]!) +
      parseInt(timeMatch[8]!) / 1000;

    const text = lines.slice(2).join(" ").trim();
    if (text) {
      segments.push({ start: startSec, end: endSec, text });
    }
  }

  return segments;
}

function formatSubtitles(segments: TranscriptSegment[], format: SubtitleFormat): string {
  const formatTime = (seconds: number, useDot: boolean = false): string => {
    const h = Math.floor(seconds / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    const s = Math.floor(seconds % 60);
    const ms = Math.floor((seconds % 1) * 1000);
    const sep = useDot ? "." : ",";
    return `${h.toString().padStart(2, "0")}:${m.toString().padStart(2, "0")}:${s.toString().padStart(2, "0")}${sep}${ms.toString().padStart(3, "0")}`;
  };

  switch (format) {
    case "srt":
      return segments
        .map(
          (seg, i) => `${i + 1}\n${formatTime(seg.start)} --> ${formatTime(seg.end)}\n${seg.text}\n`
        )
        .join("\n");

    case "vtt":
      return (
        "WEBVTT\n\n" +
        segments.map((seg) => `${formatTime(seg.start, true)} --> ${formatTime(seg.end, true)}\n${seg.text}\n`).join("\n")
      );

    case "txt":
      return segments.map((seg) => seg.text).join("\n");

    default:
      return segments.map((seg) => seg.text).join("\n");
  }
}

async function embedSubtitles(videoFile: string, subtitleFile: string, format: SubtitleFormat): Promise<void> {
  const ext = extname(videoFile);
  const outputFile = videoFile.replace(ext, `.subtitled${ext}`);

  log("INFO", "Embedding subtitles", { video: videoFile, subs: subtitleFile, output: outputFile });
  await updateState({ text: "Embedding subtitles...", isRecording: true, mode: "transcribe", progress: "95%" });

  try {
    // For MKV, we can add subtitles as a stream; for MP4, we burn them in
    if (ext === ".mkv") {
      await $`ffmpeg -y -i ${videoFile} -i ${subtitleFile} -c copy -c:s srt ${outputFile}`.quiet();
    } else {
      // Burn subtitles into video for maximum compatibility
      await $`ffmpeg -y -i ${videoFile} -vf subtitles=${subtitleFile} -c:a copy ${outputFile}`.quiet();
    }
    log("INFO", "Subtitles embedded", { output: outputFile });
  } catch (e) {
    throw new Error(`Subtitle embedding failed: ${e}`);
  }
}

// --- Overlay Integration ---

async function startOverlay() {
  await updateState({ text: "Starting overlay...", isRecording: true, mode: "live" });

  try {
    const overlayCmd = `${process.argv[0]} ${process.argv[1]} source`;

    // Get custom overlay options from args
    const position = getArg("--position") || "top";
    const fontSize = getArg("--font-size") || "32";
    const color = getArg("--color") || "#ffffff";
    const opacity = getArg("--opacity") || "0.95";
    const lines = getArg("--lines") || "2";
    const interval = getArg("--interval") || "150";

    const env = {
      ...process.env,
      OVERLAY_COMMAND: overlayCmd,
      LYRICS_POSITION: position,
      LYRICS_LINES: lines,
      LYRICS_FONT_SIZE: fontSize,
      LYRICS_COLOR: color,
      LYRICS_OPACITY: opacity,
      LYRICS_UPDATE_INTERVAL: interval,
      LYRICS_SHADOW: "true",
    };

    Bun.spawn(["toggle-lyrics-overlay", "show"], {
      env,
      stdio: ["ignore", "ignore", "ignore"],
      detached: true,
    }).unref();

    log("INFO", "Overlay started", { position, fontSize });
  } catch (e) {
    log("WARN", "Failed to start overlay", e);
  }
}

// --- Model Resolution ---

async function findWhisperBinary(): Promise<string | null> {
  try {
    await $`which whisper-stream`.quiet();
    return "whisper-stream";
  } catch {
    return null;
  }
}

async function resolveModel(input: string | null): Promise<string> {
  if (input) {
    if (input.includes("/")) {
      if (existsSync(input)) return input;
      throw new Error(`Model file not found: ${input}`);
    }
    return await ensureModelDownloaded(input);
  }
  return await ensureModelDownloaded(CONFIG.defaultModelName);
}

async function ensureModelDownloaded(modelName: string): Promise<string> {
  const expectedFilename = `ggml-${modelName}.bin`;
  const cachedPath = join(CONFIG.userModelDir, expectedFilename);

  if (existsSync(cachedPath)) {
    log("INFO", "Using cached model", { path: cachedPath });
    return cachedPath;
  }

  log("INFO", "Model not found, downloading", { model: modelName, target: CONFIG.userModelDir });
  await updateState({ text: `Downloading ${modelName}...`, isRecording: true, mode: "live" });

  try {
    await $`which whisper-cpp-download-ggml-model`.quiet();
  } catch {
    throw new Error("whisper-cpp-download-ggml-model not found in PATH");
  }

  mkdirSync(CONFIG.userModelDir, { recursive: true });

  try {
    await $`cd ${CONFIG.userModelDir} && whisper-cpp-download-ggml-model ${modelName}`;

    if (existsSync(cachedPath)) {
      log("INFO", "Model downloaded", { path: cachedPath });
      return cachedPath;
    }
    throw new Error("Download completed but model file not found");
  } catch (e) {
    throw new Error(`Failed to download model '${modelName}': ${e}`);
  }
}

// --- Helpers ---

async function getRunningPid(): Promise<number | null> {
  const file = Bun.file(CONFIG.pidFile);
  if (await file.exists()) {
    try {
      const pid = parseInt(await file.text());
      process.kill(pid, 0); // Check if process exists
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
      } catch {
        // Ignore parse errors
      }
    }
    state = { ...state, ...newState };
    await Bun.write(CONFIG.stateFile, JSON.stringify(state));
  } catch {
    // Ignore state update errors
  }
}

async function cleanup() {
  try {
    await $`toggle-lyrics-overlay hide`.quiet().catch(() => {});
    if (existsSync(CONFIG.pidFile)) unlinkSync(CONFIG.pidFile);
    if (existsSync(CONFIG.stateFile)) unlinkSync(CONFIG.stateFile);
  } catch {
    // Ignore cleanup errors
  }
}

function getArg(flag: string): string | null {
  const index = args.indexOf(flag);
  if (index !== -1 && index + 1 < args.length) {
    return args[index + 1]!;
  }
  return null;
}

function buildTooltip(state: State): string {
  const lines: string[] = [];

  const modeLabel = state.mode === "live" ? "Live Dictation" : state.mode === "transcribe" ? "Transcribing" : "Idle";
  lines.push(`<b>${modeLabel}</b>`);

  if (state.file) {
    lines.push(`File: ${basename(state.file)}`);
  }

  if (state.progress) {
    lines.push(`Progress: ${state.progress}`);
  }

  if (state.startTime) {
    const elapsed = Math.floor((Date.now() - state.startTime) / 1000);
    const mins = Math.floor(elapsed / 60);
    const secs = elapsed % 60;
    lines.push(`Time: ${mins}:${secs.toString().padStart(2, "0")}`);
  }

  if (state.error) {
    lines.push(`<span color='#ff6b6b'>Error: ${state.error}</span>`);
  }

  lines.push("");
  lines.push(`<b>► ${state.text}</b>`);

  return lines.join("\n");
}

function printHelp() {
  console.log(`
Dictation - Speech-to-text using whisper-cpp

COMMANDS:
  toggle              Start/Stop live dictation daemon
  run                 Run daemon directly (internal use)
  status              Output JSON status (for waybar)
  source              Output JSON for overlay (internal)
  transcribe <file>   Transcribe media file to subtitles
  help                Show this help

LIVE DICTATION OPTIONS:
  --model <name|path> Whisper model (default: ${CONFIG.defaultModelName})
  --no-overlay        Disable visual overlay
  --no-type           Disable automatic typing (wtype)
  --position <pos>    Overlay position: top, bottom, center (default: top)
  --font-size <n>     Overlay font size (default: 32)
  --color <hex>       Overlay text color (default: #ffffff)
  --opacity <n>       Overlay opacity 0-1 (default: 0.95)
  --lines <n>         Number of lines in overlay (default: 2)
  --interval <ms>     Overlay update interval (default: 150)

TRANSCRIBE OPTIONS:
  --model <name|path> Whisper model (default: ${CONFIG.defaultModelName})
  --format <fmt>      Output format: srt, vtt, txt (default: srt)
  --output <file>     Output file path (default: input.srt)
  --language <lang>   Language code (default: en)
  --embed             Embed subtitles into video (ffmpeg)

SUPPORTED FORMATS:
  Audio: ${CONFIG.supportedAudio.join(", ")}
  Video: ${CONFIG.supportedVideo.join(", ")}

EXAMPLES:
  dictation toggle                          # Start/stop live dictation
  dictation transcribe video.mp4            # Generate video.srt
  dictation transcribe audio.mp3 --format vtt --output out.vtt
  dictation transcribe movie.mkv --embed    # Create movie.subtitled.mkv
  dictation toggle --model large --position bottom

LOG FILES:
  Daemon logs: /tmp/dictation.out.log, /tmp/dictation.err.log
  Debug log:   ${CONFIG.logFile}
`);
}
