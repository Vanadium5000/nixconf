#!/usr/bin/env bun
import { writeFileSync, readFileSync, existsSync } from "fs";
import { $ } from "bun";

const STATE_FILE = "/tmp/pomodoro_state.json";
const CONFIG_FILE = "/tmp/pomodoro_config.json";

interface Config {
  workTime: number;
  breakTime: number;
  longBreakTime: number;
  sessionsBeforeLongBreak: number;
}

interface State {
  mode: "work" | "break" | "longbreak";
  timeLeft: number;
  isRunning: boolean;
  lastUpdated: number;
  sessionsCompleted: number;
}

function loadConfig(): Config {
  if (existsSync(CONFIG_FILE)) {
    try {
      return JSON.parse(readFileSync(CONFIG_FILE, "utf-8"));
    } catch (e) {
      console.error("Error loading config:", e);
    }
  }
  return {
    workTime: 25 * 60,
    breakTime: 5 * 60,
    longBreakTime: 15 * 60,
    sessionsBeforeLongBreak: 4,
  };
}

function saveConfig(config: Config) {
  writeFileSync(CONFIG_FILE, JSON.stringify(config, null, 2));
}

function loadState(): State {
  if (existsSync(STATE_FILE)) {
    try {
      const state = JSON.parse(readFileSync(STATE_FILE, "utf-8"));
      // Update timeLeft if running
      if (state.isRunning) {
        const now = Date.now();
        const elapsed = Math.floor((now - state.lastUpdated) / 1000);
        state.timeLeft = Math.max(0, state.timeLeft - elapsed);
        state.lastUpdated = now;

        // Auto-transition when timer hits 0
        if (state.timeLeft === 0) {
          const config = loadConfig();
          notifyEnd(state.mode);

          // Move to next phase
          if (state.mode === "work") {
            state.sessionsCompleted++;
            // Check if it's time for a long break
            if (
              state.sessionsCompleted % config.sessionsBeforeLongBreak ===
              0
            ) {
              state.mode = "longbreak";
              state.timeLeft = config.longBreakTime;
            } else {
              state.mode = "break";
              state.timeLeft = config.breakTime;
            }
          } else {
            // After any break, go back to work
            state.mode = "work";
            state.timeLeft = config.workTime;
          }

          // Keep running after transition
          state.isRunning = true;
          state.lastUpdated = Date.now();
        }
      }
      return state;
    } catch (e) {
      console.error("Error loading state:", e);
    }
  }

  const config = loadConfig();
  return {
    mode: "work",
    timeLeft: config.workTime,
    isRunning: true, // Start running by default
    lastUpdated: Date.now(),
    sessionsCompleted: 0,
  };
}

function saveState(state: State) {
  state.lastUpdated = Date.now();
  writeFileSync(STATE_FILE, JSON.stringify(state));
}

interface QuoteResponse {
  q: string;
  a: string;
  h: string;
}

async function fetchQuote(): Promise<string> {
  try {
    const res = await fetch("https://zenquotes.io/api/random");
    const data = (await res.json()) as QuoteResponse[];
    if (data && data[0]) {
      return `"${data[0].q}"\n— ${data[0].a}`;
    }
  } catch (e) {
    console.error("Failed to fetch quote:", e);
  }
  return "Stay focused!";
}

async function notifyEnd(mode: "work" | "break" | "longbreak") {
  const title =
    mode === "work"
      ? "Work session finished!"
      : mode === "longbreak"
      ? "Long break finished!"
      : "Break finished!";
  const quote =
    mode === "work" ? await fetchQuote() : "Time to get back to work!";

  try {
    await $`notify-send -i timer-symbolic ${title} ${quote}`.quiet();
  } catch (e) {
    console.error("Failed to send notification:", e);
  }

  try {
    await $`canberra-gtk-play -i complete`.quiet();
  } catch (e) {
    // canberra might not be installed
  }
}

function formatTime(seconds: number): string {
  const mins = Math.floor(seconds / 60);
  const secs = seconds % 60;
  return `${mins}:${secs.toString().padStart(2, "0")}`;
}

function printHelp() {
  console.log(`Pomodoro Timer - CLI Options

Usage: pomodoro [command] [options]

Commands:
  status              Show current timer status (default, outputs JSON for Waybar)
  toggle              Toggle pause/resume timer
  start               Start the timer
  pause               Pause the timer
  stop                Stop and reset timer
  skip                Skip to next phase (work -> break -> work)
  reset               Reset to work phase
  info                Show human-readable status
  
Config Commands:
  config              Show current configuration
  set-work <mins>     Set work duration in minutes
  set-break <mins>    Set short break duration in minutes
  set-long <mins>     Set long break duration in minutes
  set-sessions <n>    Set number of sessions before long break

Examples:
  pomodoro toggle          # Pause or resume
  pomodoro set-work 45     # Set 45-minute work sessions
  pomodoro set-break 10    # Set 10-minute breaks
  pomodoro info            # Show current status
  pomodoro skip            # Skip to next phase
  
For Waybar integration, use the default 'status' command.
`);
}

const args = Bun.argv.slice(2);
const command = args[0] || "status";

// Handle help
if (command === "help" || command === "--help" || command === "-h") {
  printHelp();
  process.exit(0);
}

let state = loadState();
const config = loadConfig();

// Handle commands
switch (command) {
  case "toggle":
    state.isRunning = !state.isRunning;
    state.lastUpdated = Date.now();
    saveState(state);
    break;

  case "start":
    state.isRunning = true;
    state.lastUpdated = Date.now();
    saveState(state);
    break;

  case "pause":
    state.isRunning = false;
    saveState(state);
    break;

  case "skip":
    if (state.mode === "work") {
      state.sessionsCompleted++;
      if (state.sessionsCompleted % config.sessionsBeforeLongBreak === 0) {
        state.mode = "longbreak";
        state.timeLeft = config.longBreakTime;
      } else {
        state.mode = "break";
        state.timeLeft = config.breakTime;
      }
    } else {
      state.mode = "work";
      state.timeLeft = config.workTime;
    }
    state.isRunning = true;
    state.lastUpdated = Date.now();
    saveState(state);
    break;

  case "reset":
  case "stop":
    state.mode = "work";
    state.timeLeft = config.workTime;
    state.isRunning = false;
    state.sessionsCompleted = 0;
    saveState(state);
    break;

  case "info":
    const modeText =
      state.mode === "work"
        ? "Work"
        : state.mode === "longbreak"
        ? "Long Break"
        : "Break";
    console.log(`
Pomodoro Timer Status
━━━━━━━━━━━━━━━━━━━━━
Mode:              ${modeText}
Time Remaining:    ${formatTime(state.timeLeft)}
Status:            ${state.isRunning ? "Running ▶" : "Paused ⏸"}
Sessions Complete: ${state.sessionsCompleted}
Next Long Break:   ${
      config.sessionsBeforeLongBreak -
      (state.sessionsCompleted % config.sessionsBeforeLongBreak)
    } sessions away

Configuration:
  Work Time:       ${config.workTime / 60} minutes
  Break Time:      ${config.breakTime / 60} minutes
  Long Break:      ${config.longBreakTime / 60} minutes
  Sessions/Cycle:  ${config.sessionsBeforeLongBreak}
`);
    process.exit(0);

  case "config":
    console.log(JSON.stringify(config, null, 2));
    process.exit(0);

  case "set-work":
    if (!args[1] || isNaN(parseInt(args[1]))) {
      console.error("Error: Please provide work time in minutes");
      process.exit(1);
    }
    config.workTime = parseInt(args[1]) * 60;
    saveConfig(config);
    console.log(`Work time set to ${args[1]} minutes`);
    process.exit(0);

  case "set-break":
    if (!args[1] || isNaN(parseInt(args[1]))) {
      console.error("Error: Please provide break time in minutes");
      process.exit(1);
    }
    config.breakTime = parseInt(args[1]) * 60;
    saveConfig(config);
    console.log(`Break time set to ${args[1]} minutes`);
    process.exit(0);

  case "set-long":
    if (!args[1] || isNaN(parseInt(args[1]))) {
      console.error("Error: Please provide long break time in minutes");
      process.exit(1);
    }
    config.longBreakTime = parseInt(args[1]) * 60;
    saveConfig(config);
    console.log(`Long break time set to ${args[1]} minutes`);
    process.exit(0);

  case "set-sessions":
    if (!args[1] || isNaN(parseInt(args[1]))) {
      console.error("Error: Please provide number of sessions");
      process.exit(1);
    }
    config.sessionsBeforeLongBreak = parseInt(args[1]);
    saveConfig(config);
    console.log(`Sessions before long break set to ${args[1]}`);
    process.exit(0);

  case "status":
  default:
    // Output JSON for Waybar
    break;
}

saveState(state);

const icon =
  state.mode === "work" ? "󱎫" : state.mode === "longbreak" ? "󱎮" : "󱎮";
const statusText = state.isRunning ? "Running" : "Paused";
const maxTime =
  state.mode === "work"
    ? config.workTime
    : state.mode === "longbreak"
    ? config.longBreakTime
    : config.breakTime;
const percentage = 1 - state.timeLeft / maxTime;

console.log(
  JSON.stringify({
    text: `${icon} ${formatTime(state.timeLeft)}`,
    tooltip: `Mode: ${
      state.mode
    }\nStatus: ${statusText}\nTime Left: ${formatTime(
      state.timeLeft
    )}\nSessions: ${state.sessionsCompleted}`,
    class: state.mode,
    percentage: percentage,
  })
);
