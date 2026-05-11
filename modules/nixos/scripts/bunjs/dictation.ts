#!/usr/bin/env bun
/**
 * dictation.ts - small, restartable speech-to-text package.
 *
 * Live dictation intentionally records first, transcribes once, then types the
 * final text. The STT backend is isolated behind SpeechBackend so the local
 * whisper.cpp implementation can be replaced by an online backend later.
 */

import { $ } from "bun";
import { basename, extname, join } from "node:path";
import { homedir, tmpdir } from "node:os";
import { existsSync } from "node:fs";
import { appendFile, mkdir, unlink } from "node:fs/promises";

const HOST = process.env.HOST || "unknown";
const IS_MACBOOK = HOST === "macbook";

const CONFIG = {
  pidFile: join(tmpdir(), "dictation.pid"),
  stateFile: join(tmpdir(), "dictation-state.json"),
  controlFile: join(tmpdir(), "dictation-control.json"),
  logFile: join(tmpdir(), "dictation.log"),
  outLog: join(tmpdir(), "dictation.out.log"),
  errLog: join(tmpdir(), "dictation.err.log"),
  configDir: join(homedir(), ".config", "dictation"),
  configFile: join(homedir(), ".config", "dictation", "config.json"),
  userModelDir: join(homedir(), ".cache", "whisper"),
  defaultModelName: IS_MACBOOK ? "base.en" : "medium.en",
  supportedAudio: [".mp3", ".wav", ".flac", ".ogg", ".m4a", ".aac", ".wma"],
  supportedVideo: [".mp4", ".mkv", ".avi", ".mov", ".webm", ".wmv", ".flv"],
} as const;

type Mode =
  | "idle"
  | "recording"
  | "transcribing"
  | "downloading"
  | "done"
  | "error";
type ControlAction = "finish" | "cancel";
type SubtitleFormat = "srt" | "vtt" | "txt";

interface UserConfig {
  pulseSource?: string;
  inputLabel?: string;
  backend?: "whisper-cpp";
  typeResult?: boolean;
}

interface State {
  mode: Mode;
  isRecording: boolean;
  text: string;
  volume: number;
  startedAt?: number;
  file?: string;
  error?: string;
  progress?: string;
  backend?: string;
  device?: string;
}

interface ControlCommand {
  id: number;
  action: ControlAction;
}

interface TranscriptSegment {
  start: number;
  end: number;
  text: string;
}

interface SpeechBackend {
  readonly name: string;
  transcribeWav(wavFile: string): Promise<string>;
  transcribeMedia(inputFile: string): Promise<TranscriptSegment[]>;
}

const args = Bun.argv.slice(2);
const command = args[0] || "help";
let stateWrite: Promise<void> = Promise.resolve();

switch (command) {
  case "toggle":
    await handleToggle();
    break;
  case "start":
    await handleStart();
    break;
  case "run":
    await handleRun();
    break;
  case "finish":
  case "stop":
    await handleSignal("finish");
    break;
  case "cancel":
    await handleSignal("cancel");
    break;
  case "cmd":
    await handleLegacyCommand();
    break;
  case "status":
  case "source":
    await handleStatus(command === "source");
    break;
  case "select-device":
    await handleSelectDevice();
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

async function handleToggle() {
  const pid = await getRunningPid();
  if (pid) {
    await log("INFO", "Toggle requested: finishing active recording", { pid });
    await sendControl("finish");
    console.log("Dictation finishing...");
    return;
  }
  await handleStart();
}

async function handleStart() {
  if (await getRunningPid()) {
    console.log(
      "Dictation is already recording. Run `dictation finish` or press the toggle key again.",
    );
    return;
  }

  await log("INFO", "Starting dictation worker", { host: HOST });
  Bun.spawn([process.argv[0]!, process.argv[1]!, "run", ...args.slice(1)], {
    stdio: ["ignore", Bun.file(CONFIG.outLog), Bun.file(CONFIG.errLog)],
    detached: true,
    env: { ...process.env },
  }).unref();

  for (let i = 0; i < 30; i++) {
    await Bun.sleep(100);
    if (await getRunningPid()) {
      console.log(
        "Dictation recording. Toggle again to finish, or run `dictation cancel`.",
      );
      return;
    }
  }

  console.error(`Failed to start dictation. See ${CONFIG.errLog}`);
  process.exit(1);
}

async function handleSignal(action: ControlAction) {
  const pid = await getRunningPid();
  if (!pid) {
    console.log("Dictation is not running.");
    await updateState(idleState());
    await closeOverlay();
    return;
  }
  await log("INFO", "Sending control action", { action, pid });
  await sendControl(action);
  console.log(
    action === "finish" ? "Dictation finishing..." : "Dictation cancelled.",
  );
}

async function handleRun() {
  const modelArg = getArg("--model");
  const noOverlay = args.includes("--no-overlay");
  const noType = args.includes("--no-type");
  const config = await loadUserConfig();
  const wavFile = join(tmpdir(), `dictation-${Date.now()}.wav`);
  const backend = new WhisperCppBackend(modelArg);
  let recorder: Subprocess | null = null;
  let outcome: ControlAction | "error" | null = null;

  await Bun.write(CONFIG.pidFile, String(process.pid));
  await removeFile(CONFIG.controlFile);
  await updateState({
    mode: "recording",
    isRecording: true,
    text: "Listening...",
    volume: 0,
    startedAt: Date.now(),
    file: wavFile,
    backend: backend.name,
    device: config.inputLabel || config.pulseSource || "default",
  });
  await log("INFO", "Worker ready", {
    pid: process.pid,
    wavFile,
    backend: backend.name,
  });
  if (!noOverlay) await showOverlay();

  const shutdown = async (action: ControlAction) => {
    outcome = action;
    recorder?.kill("SIGINT");
  };
  process.on("SIGINT", () => void shutdown("cancel"));
  process.on("SIGTERM", () => void shutdown("cancel"));

  try {
    recorder = await startRecorder(wavFile, config.pulseSource);
    const recorderExit = recorder.exited.then((code) => ({
      type: "recorder" as const,
      code,
    }));
    const control = waitForControl(async (action) => shutdown(action)).then(
      () => ({ type: "control" as const }),
    );
    const first = await Promise.race([recorderExit, control]);
    const exitCode =
      first.type === "recorder" ? first.code : await recorder.exited;
    if (first.type === "recorder" && outcome === null) {
      throw new Error(`Recorder stopped unexpectedly with code ${exitCode}`);
    }

    if (outcome === "cancel") {
      await log("INFO", "Recording cancelled", { wavFile });
      await updateState({ ...idleState(), text: "Cancelled" });
      return;
    }

    await updateState({
      mode: "transcribing",
      isRecording: false,
      text: "Transcribing...",
      volume: 0,
      progress: "working",
    });
    const text = normalizeWhitespace(await backend.transcribeWav(wavFile));
    if (!text) {
      await log("WARN", "Transcription returned no text");
      await updateState({
        mode: "done",
        isRecording: false,
        text: "No speech detected",
        volume: 0,
      });
      return;
    }

    await updateState({
      mode: "done",
      isRecording: false,
      text,
      volume: 0,
      progress: "100%",
    });
    await log("INFO", "Dictation complete", {
      chars: text.length,
      typeResult: config.typeResult !== false && !noType,
    });
    if (config.typeResult !== false && !noType) await typeText(text);
    await Bun.sleep(900);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    outcome = "error";
    await log("ERROR", "Dictation failed", { error: message });
    await updateState({
      mode: "error",
      isRecording: false,
      text: "Dictation failed",
      volume: 0,
      error: message,
    });
    process.exitCode = 1;
  } finally {
    recorder?.kill("SIGKILL");
    await removeFile(wavFile);
    await cleanupRuntime(outcome !== "error");
  }
}

async function startRecorder(
  wavFile: string,
  pulseSource?: string,
): Promise<Subprocess> {
  const input = pulseSource || "default";
  const proc = Bun.spawn(
    [
      "ffmpeg",
      "-hide_banner",
      "-loglevel",
      "info",
      "-f",
      "pulse",
      "-i",
      input,
      "-ac",
      "1",
      "-ar",
      "16000",
      "-af",
      "astats=metadata=1:reset=1,ametadata=print:key=lavfi.astats.Overall.RMS_level",
      "-c:a",
      "pcm_s16le",
      "-y",
      wavFile,
    ],
    {
      stdin: "ignore",
      stdout: "ignore",
      stderr: "pipe",
      env: { ...process.env },
    },
  );

  void readRecorderStderr(proc.stderr, proc.pid);
  await log("INFO", "Recorder started", { pid: proc.pid, input });
  return proc;
}

async function readRecorderStderr(
  stream: ReadableStream,
  pid: number | undefined,
) {
  const reader = stream.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split(/\r?\n/);
      buffer = lines.pop() || "";
      for (const line of lines) {
        const match = line.match(/lavfi\.astats\.Overall\.RMS_level=([-\d.]+)/);
        if (!match) continue;
        const db = Number(match[1]);
        if (!Number.isFinite(db)) continue;
        const volume = Math.max(0, Math.min(1, (db + 55) / 55));
        await updateState({ volume, text: "Listening..." });
      }
    }
  } catch (error) {
    await log("WARN", "Recorder stderr reader stopped", {
      pid,
      error: String(error),
    });
  }
}

async function waitForControl(
  onAction: (action: ControlAction) => Promise<void>,
) {
  let lastId = 0;
  while (true) {
    const cmd = await readControl(lastId);
    if (cmd) {
      lastId = cmd.id;
      await removeFile(CONFIG.controlFile);
      await onAction(cmd.action);
      return;
    }
    const statePid = await getRunningPid();
    if (!statePid) {
      await onAction("cancel");
      return;
    }
    await Bun.sleep(80);
  }
}

class WhisperCppBackend implements SpeechBackend {
  readonly name = "whisper-cpp";
  constructor(private readonly modelArg: string | null) {}

  async transcribeWav(wavFile: string): Promise<string> {
    await assertCommand("whisper-cli");
    const modelPath = await resolveModel(this.modelArg);
    await log("INFO", "Running whisper-cli", {
      file: basename(wavFile),
      model: basename(modelPath),
    });
    const result = Bun.spawn(
      ["whisper-cli", "-m", modelPath, "-f", wavFile, "-nt", "-np"],
      {
        stdout: "pipe",
        stderr: "pipe",
      },
    );
    const [stdout, stderr, exitCode] = await Promise.all([
      new Response(result.stdout).text(),
      new Response(result.stderr).text(),
      result.exited,
    ]);
    if (exitCode !== 0)
      throw new Error(`whisper-cli failed (${exitCode}): ${lastLine(stderr)}`);
    return cleanWhisperText(stdout || stderr);
  }

  async transcribeMedia(inputFile: string): Promise<TranscriptSegment[]> {
    await assertCommand("whisper-cli");
    const wavFile = await prepareAudioFile(inputFile);
    try {
      const modelPath = await resolveModel(this.modelArg);
      await log("INFO", "Running media transcription", {
        input: basename(inputFile),
        model: basename(modelPath),
      });
      const output = await $`whisper-cli -m ${modelPath} -f ${wavFile}`.text();
      return parseWhisperSegments(output);
    } finally {
      if (wavFile !== inputFile) await removeFile(wavFile);
    }
  }
}

async function handleLegacyCommand() {
  const legacy = args[1];
  if (legacy === "stop" || legacy === "hide" || legacy === "finish")
    return handleSignal("finish");
  if (
    legacy === "cancel" ||
    legacy === "clear" ||
    legacy === "pause" ||
    legacy === "resume"
  )
    return handleSignal("cancel");
  console.error(`Unknown command: dictation cmd ${legacy || ""}`);
  process.exit(1);
}

async function handleStatus(sourceMode = false) {
  const pid = await getRunningPid();
  const state = await loadState();
  const running = !!pid;
  const active = running && state.isRecording;
  const displayState = running || state.mode === "error" ? state : idleState();
  const status = {
    active,
    text: displayState.text || (active ? "Listening..." : "Ready"),
    mode: running
      ? displayState.mode
      : displayState.mode === "error"
        ? "error"
        : "idle",
    error: displayState.error,
    progress: displayState.progress,
    volume: active ? state.volume || 0 : 0,
    backend: displayState.backend,
    device: displayState.device,
    uptime:
      running && displayState.startedAt
        ? Math.max(0, Math.floor((Date.now() - displayState.startedAt) / 1000))
        : 0,
  };

  if (!sourceMode) {
    console.log(JSON.stringify(status));
    return;
  }

  const klass =
    status.mode === "error"
      ? "error"
      : active
        ? "playing"
        : status.mode === "done"
          ? "done"
          : "stopped";
  console.log(
    JSON.stringify({
      text: `${volumeBars(status.volume)} ${status.text}`.trim(),
      tooltip: buildTooltip(status),
      class: klass,
      alt: klass,
    }),
  );
}

async function handleSelectDevice() {
  const sources = await listPulseSources();
  if (sources.length === 0) {
    console.error("No PulseAudio/PipeWire input sources found.");
    process.exit(1);
  }

  const config = await loadUserConfig();
  const lines = sources.map(
    (s) => `${s.label}${s.name === config.pulseSource ? " [current]" : ""}`,
  );
  const result = await $`printf '%s\n' ${lines} | qs-dmenu -p "Dictation mic"`
    .nothrow()
    .quiet();
  const selectedLabel = result
    .text()
    .trim()
    .replace(/ \[current\]$/, "");
  const selected = sources.find((s) => s.label === selectedLabel);
  if (!selected || result.exitCode !== 0) {
    console.log("No device selected.");
    return;
  }

  await saveUserConfig({
    ...config,
    pulseSource: selected.name,
    inputLabel: selected.label,
  });
  await log("INFO", "Selected input device", selected);
  console.log(`Selected: ${selected.label}`);
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
  const supported = [
    ...CONFIG.supportedAudio,
    ...CONFIG.supportedVideo,
  ].includes(ext as never);
  if (!supported) {
    console.error(`Unsupported media format: ${ext}`);
    process.exit(1);
  }

  const format = (getArg("--format") || "srt") as SubtitleFormat;
  const outPath = getArg("--output") || inputFile.replace(ext, `.${format}`);
  const backend = new WhisperCppBackend(getArg("--model"));
  await updateState({
    mode: "transcribing",
    isRecording: false,
    text: `Transcribing ${basename(inputFile)}`,
    volume: 0,
    startedAt: Date.now(),
  });
  try {
    const segments = await backend.transcribeMedia(inputFile);
    await Bun.write(outPath, formatSubtitles(segments, format));
    if (
      args.includes("--embed") &&
      CONFIG.supportedVideo.includes(ext as never)
    )
      await embedSubtitles(inputFile, outPath);
    await updateState({
      mode: "done",
      isRecording: false,
      text: `Saved ${basename(outPath)}`,
      progress: "100%",
      volume: 0,
    });
    await log("INFO", "Media transcription complete", {
      outPath,
      segments: segments.length,
    });
    console.log(`Done: ${outPath}`);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    await updateState({
      mode: "error",
      isRecording: false,
      text: "Transcription failed",
      error: message,
      volume: 0,
    });
    await log("ERROR", "Media transcription failed", { error: message });
    console.error(message);
    process.exit(1);
  }
}

async function prepareAudioFile(inputFile: string): Promise<string> {
  if (extname(inputFile).toLowerCase() === ".wav") return inputFile;
  await assertCommand("ffmpeg");
  const outputWav = join(tmpdir(), `dictation-media-${Date.now()}.wav`);
  await log("INFO", "Preparing media audio", {
    input: basename(inputFile),
    output: basename(outputWav),
  });
  await $`ffmpeg -hide_banner -loglevel error -y -i ${inputFile} -ar 16000 -ac 1 -c:a pcm_s16le ${outputWav}`.quiet();
  return outputWav;
}

async function resolveModel(input: string | null): Promise<string> {
  const modelName = input || CONFIG.defaultModelName;
  if (modelName.includes("/")) {
    if (existsSync(modelName)) return modelName;
    throw new Error(`Model not found: ${modelName}`);
  }
  const path = join(CONFIG.userModelDir, `ggml-${modelName}.bin`);
  if (existsSync(path)) return path;

  await updateState({
    mode: "downloading",
    isRecording: true,
    text: `Downloading ${modelName}...`,
    progress: "0%",
    volume: 0,
  });
  await mkdir(CONFIG.userModelDir, { recursive: true });
  await assertCommand("whisper-cpp-download-ggml-model");
  await log("INFO", "Downloading whisper model", {
    modelName,
    dir: CONFIG.userModelDir,
  });
  const proc = Bun.spawn(["whisper-cpp-download-ggml-model", modelName], {
    cwd: CONFIG.userModelDir,
    stdout: "pipe",
    stderr: "pipe",
  });
  void readDownloadProgress(proc.stdout, modelName);
  const stderr = await new Response(proc.stderr).text();
  const code = await proc.exited;
  if (code !== 0 || !existsSync(path))
    throw new Error(`Model download failed: ${lastLine(stderr)}`);
  return path;
}

async function assertCommand(name: string) {
  const result = await $`which ${name}`.nothrow().quiet();
  if (result.exitCode !== 0) {
    throw new Error(
      `${name} not found in PATH. Install whisper-cpp in the system profile or pass a backend that provides it.`,
    );
  }
}

async function readDownloadProgress(stream: ReadableStream, modelName: string) {
  const reader = stream.getReader();
  const decoder = new TextDecoder();
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    const text = decoder.decode(value);
    const match = text.match(/(\d+)%/);
    if (match)
      await updateState({
        mode: "downloading",
        text: `Downloading ${modelName} ${match[1]}%`,
        progress: `${match[1]}%`,
      });
  }
}

async function listPulseSources(): Promise<
  Array<{ name: string; label: string }>
> {
  const result = await $`pactl list short sources`.nothrow().quiet();
  if (result.exitCode !== 0) return [];
  return result
    .text()
    .split("\n")
    .map((line) => {
      const cols = line.split("\t");
      const name = cols[1] || "";
      return name && !name.includes(".monitor")
        ? { name, label: name.replace(/_/g, " ") }
        : null;
    })
    .filter(Boolean) as Array<{ name: string; label: string }>;
}

async function typeText(text: string) {
  const trimmed = normalizeWhitespace(text);
  if (!trimmed) return;
  try {
    await $`wtype ${trimmed}`.quiet();
    await log("INFO", "Typed transcription via wtype", {
      chars: trimmed.length,
    });
  } catch (error) {
    await log("WARN", "wtype failed; copying to clipboard instead", {
      error: String(error),
    });
    await $`wl-copy ${trimmed}`.quiet();
  }
}

async function showOverlay() {
  try {
    Bun.spawn(["toggle-dictation-overlay", "show"], {
      stdio: ["ignore", "ignore", "ignore"],
      detached: true,
    }).unref();
    await log("INFO", "Overlay shown");
  } catch (error) {
    await log("WARN", "Could not show overlay", { error: String(error) });
  }
}

async function cleanupRuntime(hideOverlay: boolean) {
  await removeFile(CONFIG.pidFile);
  await removeFile(CONFIG.controlFile);
  if (hideOverlay) await closeOverlay();
}

async function closeOverlay() {
  await $`toggle-dictation-overlay hide`.quiet().catch(() => {});
}

async function sendControl(action: ControlAction) {
  await Bun.write(
    CONFIG.controlFile,
    JSON.stringify({ id: Date.now(), action } satisfies ControlCommand),
  );
}

async function readControl(lastId: number): Promise<ControlCommand | null> {
  try {
    const file = Bun.file(CONFIG.controlFile);
    if (!(await file.exists())) return null;
    const payload = (await file.json()) as ControlCommand;
    return payload.id > lastId ? payload : null;
  } catch {
    return null;
  }
}

async function loadState(): Promise<State> {
  try {
    const file = Bun.file(CONFIG.stateFile);
    if (await file.exists()) return { ...idleState(), ...(await file.json()) };
  } catch {}
  return idleState();
}

async function updateState(next: Partial<State>) {
  stateWrite = stateWrite
    .then(async () => {
      const current = await loadState();
      await Bun.write(
        CONFIG.stateFile,
        JSON.stringify({ ...current, ...next }),
      );
    })
    .catch(() => {});
  return stateWrite;
}

function idleState(): State {
  return {
    mode: "idle",
    isRecording: false,
    text: "Ready",
    volume: 0,
    startedAt: undefined,
    file: undefined,
    error: undefined,
    progress: undefined,
    backend: undefined,
    device: undefined,
  };
}

async function getRunningPid(): Promise<number | null> {
  try {
    const file = Bun.file(CONFIG.pidFile);
    if (!(await file.exists())) return null;
    const pid = Number((await file.text()).trim());
    if (!pid) return null;
    process.kill(pid, 0);
    return pid;
  } catch {
    await removeFile(CONFIG.pidFile);
    return null;
  }
}

async function loadUserConfig(): Promise<UserConfig> {
  try {
    const file = Bun.file(CONFIG.configFile);
    if (await file.exists()) return await file.json();
  } catch {}
  return {};
}

async function saveUserConfig(config: UserConfig) {
  await mkdir(CONFIG.configDir, { recursive: true });
  await Bun.write(CONFIG.configFile, JSON.stringify(config, null, 2));
}

async function removeFile(path: string) {
  if (existsSync(path)) await unlink(path).catch(() => {});
}

async function log(
  level: "INFO" | "WARN" | "ERROR",
  message: string,
  data?: unknown,
) {
  const ts = new Date().toISOString();
  const line = `${ts} ${level.padEnd(5)} ${message}${data === undefined ? "" : ` ${JSON.stringify(data)}`}`;
  await appendFile(CONFIG.logFile, line + "\n").catch(() => {});
  if (level === "ERROR") console.error(line);
}

function normalizeWhitespace(text: string): string {
  return text.replace(/\s+/g, " ").trim();
}

function cleanWhisperText(output: string): string {
  return normalizeWhitespace(
    output
      .replace(/\x1b\[[0-9;]*[a-zA-Z]/g, "")
      .split("\n")
      .filter(
        (line) => !/^\s*(whisper_|ggml_|main:|system_info|\[\d{2}:)/.test(line),
      )
      .join(" "),
  );
}

function parseWhisperSegments(output: string): TranscriptSegment[] {
  const segments: TranscriptSegment[] = [];
  for (const line of output.split("\n")) {
    const match = line.match(
      /\[(\d{2}):(\d{2}):(\d{2})\.(\d{3})\s*-->\s*(\d{2}):(\d{2}):(\d{2})\.(\d{3})\]\s*(.*)/,
    );
    if (!match) continue;
    const start = toSeconds(match[1]!, match[2]!, match[3]!, match[4]!);
    const end = toSeconds(match[5]!, match[6]!, match[7]!, match[8]!);
    const text = normalizeWhitespace(match[9] || "");
    if (text && !/^[[({]/.test(text)) segments.push({ start, end, text });
  }
  return segments;
}

function toSeconds(h: string, m: string, s: string, ms: string): number {
  return Number(h) * 3600 + Number(m) * 60 + Number(s) + Number(ms) / 1000;
}

function formatSubtitles(
  segments: TranscriptSegment[],
  format: SubtitleFormat,
): string {
  const fmt = (seconds: number, dot = false) => {
    const h = Math.floor(seconds / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    const s = Math.floor(seconds % 60);
    const ms = Math.floor((seconds % 1) * 1000);
    return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}${dot ? "." : ","}${String(ms).padStart(3, "0")}`;
  };
  if (format === "txt") return segments.map((s) => s.text).join("\n");
  if (format === "vtt")
    return (
      "WEBVTT\n\n" +
      segments
        .map(
          (s) => `${fmt(s.start, true)} --> ${fmt(s.end, true)}\n${s.text}\n`,
        )
        .join("\n")
    );
  return segments
    .map((s, i) => `${i + 1}\n${fmt(s.start)} --> ${fmt(s.end)}\n${s.text}\n`)
    .join("\n");
}

async function embedSubtitles(videoFile: string, subtitleFile: string) {
  const ext = extname(videoFile);
  const output = videoFile.replace(ext, `.subtitled${ext}`);
  if (ext === ".mkv")
    await $`ffmpeg -y -i ${videoFile} -i ${subtitleFile} -c copy -c:s srt ${output}`.quiet();
  else
    await $`ffmpeg -y -i ${videoFile} -vf subtitles=${subtitleFile} -c:a copy ${output}`.quiet();
}

function volumeBars(volume = 0): string {
  const bars = ["▁", "▂", "▃", "▄", "▅", "▆", "▇"];
  const count = Math.max(
    1,
    Math.min(bars.length, Math.round(volume * bars.length)),
  );
  return bars.slice(0, count).join("");
}

function buildTooltip(status: {
  mode: string;
  text: string;
  device?: string;
  backend?: string;
  uptime?: number;
  error?: string;
}) {
  const lines = [
    `Dictation: ${status.mode}`,
    `Backend: ${status.backend || "whisper-cpp"}`,
  ];
  if (status.device) lines.push(`Input: ${status.device}`);
  if (status.uptime)
    lines.push(
      `Time: ${Math.floor(status.uptime / 60)}:${String(status.uptime % 60).padStart(2, "0")}`,
    );
  if (status.error) lines.push(`Error: ${status.error}`);
  lines.push("", status.text);
  return lines.join("\n");
}

function lastLine(text: string): string {
  return text.trim().split("\n").filter(Boolean).at(-1) || "unknown error";
}

function getArg(flag: string): string | null {
  const i = args.indexOf(flag);
  return i >= 0 && i + 1 < args.length ? args[i + 1]! : null;
}

function printHelp() {
  console.log(`
Dictation - simple record → transcribe → type workflow

Commands:
  dictation toggle             Start recording; run again to finish and type text
  dictation start              Start recording
  dictation finish|stop        Finish recording and transcribe
  dictation cancel             Stop recording without transcription
  dictation status             Print status JSON for widgets
  dictation source             Print compact widget JSON
  dictation select-device      Select PulseAudio/PipeWire input source
  dictation transcribe <file>  Transcribe media file to subtitles/text

Options:
  --model <name|path>          whisper.cpp model (default: ${CONFIG.defaultModelName})
  --no-overlay                 Do not show the QuickShell widget
  --no-type                    Transcribe but do not type result
  --format srt|vtt|txt         Media transcription output format
  --output <file>              Media transcription output path
  --embed                      Embed subtitles into video output

Config: ${CONFIG.configFile}
Logs:   ${CONFIG.logFile}
`);
}

type Subprocess = ReturnType<typeof Bun.spawn>;
