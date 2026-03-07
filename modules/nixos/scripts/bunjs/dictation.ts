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
  controlFile: join(tmpdir(), "dictation-control.json"),
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
  mode:
    | "idle"
    | "starting"
    | "live"
    | "paused"
    | "transcribe"
    | "downloading"
    | "error";
  error?: string;
  progress?: string;
  file?: string;
  startTime?: number;
  volume?: number;
  committedText?: string;
  activeText?: string;
}

interface TranscriptSegment {
  start: number;
  end: number;
  text: string;
}

interface ControlCommand {
  id: number;
  command: "clear" | "pause" | "resume" | "toggle-pause" | "stop" | "hide";
}

type SubtitleFormat = "srt" | "vtt" | "txt";

async function log(
  level: "INFO" | "WARN" | "ERROR",
  msg: string,
  data?: unknown,
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

// Global promise queue for atomic state updates
let statePromise: Promise<void> = Promise.resolve();

async function loadState(): Promise<State> {
  try {
    const file = Bun.file(CONFIG.stateFile);
    if (await file.exists()) {
      return await file.json();
    }
  } catch {}
  return { text: "", isRecording: false, mode: "idle" };
}

async function updateState(newState: Partial<State>) {
  statePromise = statePromise
    .then(async () => {
      try {
        const state = await loadState();
        await Bun.write(
          CONFIG.stateFile,
          JSON.stringify({ ...state, ...newState }),
        );
      } catch {}
    })
    .catch(() => {});
  return statePromise;
}

function normalizeWhitespace(text: string): string {
  return text.replace(/\s+/g, " ").trim();
}

function joinTranscriptParts(...parts: Array<string | undefined>): string {
  return normalizeWhitespace(parts.filter(Boolean).join(" "));
}

async function writeControlCommand(command: ControlCommand["command"]) {
  const payload: ControlCommand = { id: Date.now(), command };
  await Bun.write(CONFIG.controlFile, JSON.stringify(payload));
}

async function readControlCommand(
  lastProcessedId: number,
): Promise<ControlCommand | null> {
  try {
    const file = Bun.file(CONFIG.controlFile);
    if (!(await file.exists())) return null;
    const payload = (await file.json()) as ControlCommand;
    if (!payload?.id || payload.id <= lastProcessedId) return null;
    return payload;
  } catch {
    return null;
  }
}

async function clearControlCommand(id: number) {
  try {
    const file = Bun.file(CONFIG.controlFile);
    if (!(await file.exists())) return;
    const payload = (await file.json()) as Partial<ControlCommand>;
    if (payload.id === id && existsSync(CONFIG.controlFile)) {
      await unlink(CONFIG.controlFile);
    }
  } catch {}
}

function getRenderedTranscript(
  committedText?: string,
  activeText?: string,
): string {
  return joinTranscriptParts(committedText, activeText);
}

function splitIntoWords(text: string): string[] {
  return normalizeWhitespace(text).split(" ").filter(Boolean);
}

function stripCommittedPrefix(
  committedText: string,
  incomingText: string,
): string {
  const committed = normalizeWhitespace(committedText);
  const incoming = normalizeWhitespace(incomingText);
  if (!committed) return incoming;
  if (incoming.startsWith(committed)) {
    return normalizeWhitespace(incoming.slice(committed.length));
  }

  const committedWords = splitIntoWords(committed);
  const incomingWords = splitIntoWords(incoming);
  const maxOverlap = Math.min(committedWords.length, incomingWords.length);

  for (let size = maxOverlap; size > 0; size--) {
    const committedTail = committedWords.slice(-size).join(" ");
    const incomingHead = incomingWords.slice(0, size).join(" ");
    if (committedTail === incomingHead) {
      return incomingWords.slice(size).join(" ");
    }
  }

  return incoming;
}

async function setTranscriptState(
  updates: Partial<State> & {
    committedText?: string;
    activeText?: string;
  },
) {
  const current = await loadState();
  const committedText = updates.committedText ?? current.committedText ?? "";
  const activeText = updates.activeText ?? current.activeText ?? "";

  await updateState({
    ...updates,
    committedText,
    activeText,
    text: updates.text ?? getRenderedTranscript(committedText, activeText),
  });
}

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
  case "cmd":
    await handleCommand();
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
  if (existsSync(CONFIG.controlFile)) {
    await unlink(CONFIG.controlFile).catch(() => {});
  }
  await setTranscriptState({
    committedText: "",
    activeText: "Starting...",
    isRecording: true,
    mode: "starting",
    startTime: Date.now(),
    error: undefined,
    progress: undefined,
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

  let shouldExit = false;
  let finalOutcome: "paused" | "stopped" | "error" | null = null;
  let lastProcessedCommandId = 0;
  while (!shouldExit) {
    const pending = await readControlCommand(lastProcessedCommandId);
    if (pending) {
      lastProcessedCommandId = pending.id;
      const state = await loadState();

      switch (pending.command) {
        case "clear":
          await setTranscriptState({
            committedText: "",
            activeText: "",
            mode: state.mode,
            isRecording: state.isRecording,
          });
          break;
        case "pause":
        case "toggle-pause":
          if (state.mode === "paused") {
            await setTranscriptState({
              activeText: "Resuming...",
              mode: "starting",
              isRecording: false,
              volume: 0,
            });
          }
          break;
        case "resume":
          if (state.mode === "paused") {
            await setTranscriptState({
              activeText: "Resuming...",
              mode: "starting",
              isRecording: false,
              volume: 0,
            });
          }
          break;
        case "stop":
        case "hide":
          await setTranscriptState({
            activeText: "Stopped",
            mode: "idle",
            isRecording: false,
            volume: 0,
          });
          finalOutcome = "stopped";
          shouldExit = true;
          break;
      }

      await clearControlCommand(pending.id);
      if (shouldExit) break;
    }

    const state = await loadState();
    if (state.mode === "paused") {
      await Bun.sleep(150);
      continue;
    }

    const outcome = await runWhisperStream(
      whisperBin,
      modelPath,
      device.sdlId,
      device.name,
    );

    switch (outcome) {
      case "paused":
        continue;
      case "stopped":
        finalOutcome = "stopped";
        shouldExit = true;
        break;
      case "error":
        finalOutcome = "error";
        shouldExit = true;
        break;
    }
  }

  if (finalOutcome === "stopped") {
    await cleanup();
    return;
  }

  if (existsSync(CONFIG.pidFile)) {
    await unlink(CONFIG.pidFile).catch(() => {});
  }
  if (existsSync(CONFIG.controlFile)) {
    await unlink(CONFIG.controlFile).catch(() => {});
  }
}

async function handleCommand() {
  const cmd = args[1];
  switch (cmd) {
    case "clear":
      await writeControlCommand("clear");
      break;
    case "pause":
      await writeControlCommand("toggle-pause");
      break;
    case "resume":
      await writeControlCommand("resume");
      break;
    case "stop":
      await writeControlCommand("stop");
      break;
    case "hide":
      await writeControlCommand("stop");
      break;
    default:
      console.error(`Unknown internal command: ${cmd}`);
      process.exit(1);
  }
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
      }),
    );
  } catch (e) {
    console.log(
      JSON.stringify({
        active: false,
        text: "",
        mode: "error",
        error: String(e),
      }),
    );
  }
}

async function handleSource() {
  try {
    const file = Bun.file(CONFIG.stateFile);
    if (!(await file.exists())) {
      console.log(
        JSON.stringify({ text: "Ready", class: "stopped", alt: "stopped" }),
      );
      return;
    }

    const content = await file.text();
    if (!content.trim()) {
      console.log(
        JSON.stringify({ text: "Ready", class: "stopped", alt: "stopped" }),
      );
      return;
    }

    const state = JSON.parse(content) as State;
    const volBar =
      state.volume !== undefined ? getVolumeIndicator(state.volume) : "";
    const sourceClass =
      state.mode === "error"
        ? "error"
        : state.mode === "paused"
          ? "paused"
          : state.isRecording
            ? "playing"
            : "stopped";

    console.log(
      JSON.stringify({
        text: state.text ? `${volBar} ${state.text}`.trim() : volBar || "...",
        tooltip: buildTooltip(state),
        class: sourceClass,
        alt: sourceClass,
      }),
    );
  } catch (e) {
    await log("ERROR", "handleSource failed", { error: String(e) });
    console.log(
      JSON.stringify({ text: "...", class: "stopped", alt: "stopped" }),
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
  currentName?: string,
): Promise<AudioDevice | null> {
  if (devices.length === 0) return null;

  const lines = devices.map((d) => {
    const current = d.name === currentName ? " [current]" : "";
    return `${d.name}${current}`;
  });

  try {
    const result = await $`printf '%s\n' ${lines} | qs-dmenu -p "Input Device"`
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
        : "Usage: dictation transcribe <file>",
    );
    process.exit(1);
  }

  const ext = extname(inputFile).toLowerCase();
  const isVideo = CONFIG.supportedVideo.includes(
    ext as (typeof CONFIG.supportedVideo)[number],
  );
  const isAudio = CONFIG.supportedAudio.includes(
    ext as (typeof CONFIG.supportedAudio)[number],
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
          `[${formatTimestamp(s.start)} -> ${formatTimestamp(s.end)}] ${s.text}`,
        ),
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
  deviceId: number,
  deviceName?: string,
): Promise<"paused" | "stopped" | "error"> {
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
      env = { ...env, PULSE_SOURCE: pulseSource };
    } else {
      await log("WARN", "Could not resolve PulseAudio source name", {
        deviceName,
      });
    }
  }

  await setTranscriptState({
    activeText: `Loading ${modelName}...`,
    isRecording: true,
    mode: "starting",
    volume: 0,
    error: undefined,
  });

  let initialized = false;
  let expectedExit: "paused" | "stopped" | null = null;
  let lastProcessedCommandId = 0;
  let activePartial = "";
  let lastPartialChange = Date.now();

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
      "0.6",
      "-bs",
      "5",
      "-nf",
      "-c",
      "0",
    ],
    {
      stdio: ["ignore", "pipe", "pipe"],
      env,
    },
  );

  const watchdog = setTimeout(async () => {
    if (!initialized) {
      await log("ERROR", "Init timeout - no audio device response in 60s");
      await setTranscriptState({
        activeText: "❌ Timeout",
        isRecording: false,
        mode: "error",
        error: "Init timeout",
        volume: 0,
      });
      try {
        proc.kill();
      } catch {}
    }
  }, 60000);

  let lastText = "";
  let lastUpdateTime = Date.now();

  const stripAnsi = (s: string) => s.replace(/\x1b\[[0-9;]*[a-zA-Z]/g, "");

  const commitActivePartial = async () => {
    if (!activePartial) return;
    const state = await loadState();
    const nextCommitted = joinTranscriptParts(
      state.committedText,
      activePartial,
    );
    activePartial = "";
    await setTranscriptState({
      committedText: nextCommitted,
      activeText: "",
      isRecording: state.mode === "live",
      mode: state.mode,
    });
  };

  const syncPartialTranscript = async (
    incomingText: string,
    volume: number,
  ) => {
    const state = await loadState();
    const trimmedIncoming = normalizeWhitespace(incomingText);
    const baseCommitted = state.committedText ?? "";
    if (!trimmedIncoming) return;

    const nextPartial = stripCommittedPrefix(baseCommitted, trimmedIncoming);
    const now = Date.now();
    const isRevision =
      activePartial && nextPartial && activePartial !== nextPartial;
    const previousWordCount = splitIntoWords(activePartial).length;
    const nextWordCount = splitIntoWords(nextPartial).length;
    const shouldCommitPrevious =
      !!activePartial &&
      (/[.!?]$/.test(activePartial) ||
        (now - lastPartialChange > 1400 && !isRevision) ||
        (previousWordCount > 0 && nextWordCount > previousWordCount + 3));

    if (shouldCommitPrevious) {
      const nextCommitted = joinTranscriptParts(baseCommitted, activePartial);
      activePartial = nextPartial;
      lastPartialChange = now;
      await setTranscriptState({
        committedText: nextCommitted,
        activeText: nextPartial,
        isRecording: true,
        mode: "live",
        volume,
      });
      return;
    }

    activePartial = nextPartial;
    lastPartialChange = now;
    await setTranscriptState({
      activeText: nextPartial || state.activeText || "",
      isRecording: true,
      mode: "live",
      volume,
    });
  };

  const handleControlCommands = async () => {
    const pending = await readControlCommand(lastProcessedCommandId);
    if (!pending) return;

    lastProcessedCommandId = pending.id;
    const state = await loadState();
    switch (pending.command) {
      case "clear":
        activePartial = "";
        await setTranscriptState({
          committedText: "",
          activeText: "",
          mode: state.mode,
          isRecording: state.isRecording,
        });
        break;
      case "pause":
      case "toggle-pause":
        if (state.mode === "paused") {
          await setTranscriptState({
            activeText: activePartial || "Resuming...",
            isRecording: false,
            mode: "starting",
            volume: 0,
          });
        } else {
          await commitActivePartial();
          expectedExit = "paused";
          await setTranscriptState({
            activeText: "Paused",
            isRecording: false,
            mode: "paused",
            volume: 0,
          });
          try {
            proc.kill();
          } catch {}
        }
        break;
      case "resume":
        if (state.mode === "paused") {
          await setTranscriptState({
            activeText: "Resuming...",
            isRecording: false,
            mode: "starting",
            volume: 0,
          });
        }
        break;
      case "stop":
      case "hide":
        await commitActivePartial();
        expectedExit = "stopped";
        await setTranscriptState({
          activeText: "Stopped",
          isRecording: false,
          mode: "idle",
          volume: 0,
        });
        try {
          proc.kill();
        } catch {}
        break;
    }

    await clearControlCommand(pending.id);
  };

  const controlPoll = setInterval(() => {
    void handleControlCommands();
  }, 120);

  const isValidTranscript = (text: string): boolean => {
    if (!text || text.length < 2) return false;
    if (/^[\[\(].*[\]\)]$/.test(text)) {
      const inner = text.slice(1, -1).trim().toLowerCase();
      if (/^[\d:.]+$/.test(inner)) return false;
      const noiseTriggers = [
        "music",
        "applause",
        "inaudible",
        "silence",
        "noise",
        "beeping",
        "laughter",
        "sound",
        "foreign",
        "background",
        "chatter",
        "end of recording",
        "video",
        "audio",
        "transcript",
        "subtitle",
        "subtitles",
        "copyright",
        "caption",
        "notes",
        "no audio",
        "static",
        "thud",
        "buzzing",
        "chirping",
        "coughing",
        "rustling",
        "typing",
        "door",
        "footsteps",
        "wind",
        "phone",
        "ringing",
        "click",
        "pop",
        "hiss",
        "rumble",
        "whistle",
        "breathing",
      ];
      if (noiseTriggers.some((t) => inner.includes(t))) return false;
    }
    if (/^\*.*\*$/.test(text)) return false;
    if (/^Amps\s*=\s*0/i.test(text)) return false;
    if (/^Subtitles? by/i.test(text)) return false;
    if (/^[0-9]+$/.test(text)) return false;
    const dominated = [
      "init:",
      "whisper_",
      "ggml_",
      "main:",
      "system_info",
      "Device",
      "sample rate",
      "format:",
      "channels:",
      "[Start speaking]",
    ];
    for (const d of dominated) if (text.includes(d)) return false;
    return true;
  };

  const processChunk = async (chunk: string) => {
    const cleaned = stripAnsi(chunk);
    const parts = cleaned.split(/[\r\n]+/);

    for (const part of parts) {
      const text = part.replace(/[\r\n]+/g, " ").trim();
      if (!text) continue;

      if (text.includes("Capture device #")) {
        const match = text.match(/Capture device #\d+: '([^']+)'/);
        if (match) await log("INFO", "Audio device", { name: match[1] });
      }

      if (text.includes("attempt to open default capture")) {
        await log("INFO", "Opening mic");
        await setTranscriptState({
          activeText: "Opening mic...",
          isRecording: true,
          mode: "starting",
          volume: 0,
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
        const state = await loadState();
        if (state.mode === "starting" || state.mode === "live") {
          await setTranscriptState({
            activeText: activePartial || "🎤 Listening...",
            isRecording: true,
            mode: "live",
            volume: 0.2,
          });
        }
      }

      const state = await loadState();
      if (state.mode !== "live") continue;

      if (isValidTranscript(text) && text !== lastText) {
        lastText = text;
        const now = Date.now();
        if (now - lastUpdateTime > 100) {
          lastUpdateTime = now;
          await log("INFO", "Transcribed", { text: text.slice(0, 60) });
          await syncPartialTranscript(text, 0.8);
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

  clearInterval(controlPoll);
  clearTimeout(watchdog);
  const exitCode = await proc.exited;
  await log("INFO", "whisper-stream exited", { exitCode });

  if (expectedExit === "paused") {
    await setTranscriptState({
      activeText: "Paused",
      isRecording: false,
      mode: "paused",
      volume: 0,
    });
    return "paused";
  }

  if (expectedExit === "stopped") {
    await setTranscriptState({
      activeText: "Stopped",
      isRecording: false,
      mode: "idle",
      volume: 0,
    });
    return "stopped";
  }

  await commitActivePartial();
  await setTranscriptState({
    activeText: "❌ Dictation stopped unexpectedly",
    isRecording: false,
    mode: "error",
    error: `whisper-stream exited with code ${exitCode}`,
    volume: 0,
  });
  return "error";
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
  modelPath: string,
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
        /\[(\d{2}):(\d{2}):(\d{2})\.(\d{3})\s*-->\s*(\d{2}):(\d{2}):(\d{2})\.(\d{3})\]\s*(.*)/,
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
        if (text && !text.startsWith("[") && !text.startsWith("("))
          segments.push({ start, end, text });
      }
    }
    return segments;
  } catch (e) {
    throw new Error(`Transcription failed: ${e}`);
  }
}

function formatSubtitles(
  segments: TranscriptSegment[],
  format: SubtitleFormat,
): string {
  const fmt = (s: number, dot = false) => {
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    const sec = Math.floor(s % 60);
    const ms = Math.floor((s % 1) * 1000);
    return `${h.toString().padStart(2, "0")}:${m.toString().padStart(2, "0")}:${sec.toString().padStart(2, "0")}${dot ? "." : ","}${ms.toString().padStart(3, "0")}`;
  };
  if (format === "vtt")
    return (
      "WEBVTT\n\n" +
      segments
        .map(
          (s) => `${fmt(s.start, true)} --> ${fmt(s.end, true)}\n${s.text}\n`,
        )
        .join("\n")
    );
  if (format === "txt") return segments.map((s) => s.text).join("\n");
  return segments
    .map((s, i) => `${i + 1}\n${fmt(s.start)} --> ${fmt(s.end)}\n${s.text}\n`)
    .join("\n");
}

async function embedSubtitles(
  videoFile: string,
  subtitleFile: string,
): Promise<void> {
  const ext = extname(videoFile);
  const output = videoFile.replace(ext, `.subtitled${ext}`);
  try {
    if (ext === ".mkv")
      await $`ffmpeg -y -i ${videoFile} -i ${subtitleFile} -c copy -c:s srt ${output}`.quiet();
    else
      await $`ffmpeg -y -i ${videoFile} -vf subtitles=${subtitleFile} -c:a copy ${output}`.quiet();
  } catch (e) {
    throw new Error(`Embedding failed: ${e}`);
  }
}

async function startOverlay() {
  await setTranscriptState({
    activeText: "Starting overlay...",
    isRecording: true,
    mode: "starting",
  });
  try {
    Bun.spawn(["toggle-dictation-overlay", "show"], {
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
  if (existsSync(path)) return path;
  await updateState({
    text: `⬇️ Downloading ${modelName}...`,
    isRecording: true,
    mode: "downloading",
    progress: "0%",
  });
  try {
    await mkdir(CONFIG.userModelDir, { recursive: true });
    const proc = Bun.spawn(
      [
        "sh",
        "-c",
        `cd "${CONFIG.userModelDir}" && whisper-cpp-download-ggml-model "${modelName}" 2>&1`,
      ],
      { stdio: ["ignore", "pipe", "pipe"] },
    );
    const reader = proc.stdout.getReader();
    const decoder = new TextDecoder();
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      const text = decoder.decode(value);
      const match = text.match(/(\d+)%/);
      if (match)
        await updateState({
          text: `⬇️ ${modelName} ${match[1]}%`,
          isRecording: true,
          mode: "downloading",
          progress: `${match[1]}%`,
        });
    }
    await proc.exited;
    return path;
  } catch {
    throw new Error(`Download failed for ${modelName}`);
  }
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

async function cleanup() {
  try {
    await $`toggle-dictation-overlay hide`.quiet().catch(() => {});
    if (existsSync(CONFIG.pidFile)) await unlink(CONFIG.pidFile);
    if (existsSync(CONFIG.stateFile)) await unlink(CONFIG.stateFile);
    if (existsSync(CONFIG.controlFile)) await unlink(CONFIG.controlFile);
  } catch {}
}

function getArg(flag: string): string | null {
  const i = args.indexOf(flag);
  return i !== -1 && i + 1 < args.length ? args[i + 1]! : null;
}

function buildTooltip(state: State): string {
  const lines: string[] = [];
  const modeLabels: Record<State["mode"], string> = {
    starting: "⏳ Starting",
    live: "🎙️ Live",
    paused: "⏸️ Paused",
    transcribe: "📝 Transcribe",
    downloading: "⬇️ Downloading",
    error: "❌ Error",
    idle: "⏹️ Stopped",
  };
  lines.push(`<b>${modeLabels[state.mode] || state.mode}</b>`);
  if (state.file) lines.push(`File: ${basename(state.file)}`);
  if (state.progress) lines.push(`Progress: ${state.progress}`);
  if (state.startTime) {
    const s = Math.floor((Date.now() - state.startTime) / 1000);
    lines.push(
      `Time: ${Math.floor(s / 60)}:${(s % 60).toString().padStart(2, "0")}`,
    );
  }
  if (state.error) lines.push(`<span color='#fc5454'>${state.error}</span>`);
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
