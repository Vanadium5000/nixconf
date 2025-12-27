#!/usr/bin/env bun
// checklist.ts - Bun.js TypeScript script for managing daily checklists using rofi
import { $ } from "bun";
import fs from "node:fs";
import path from "node:path";

// Logging utility with timestamps
function log(level: string, message: string, ...args: any[]) {
  const timestamp = new Date().toISOString();
  console.log(`[${timestamp}] [${level}] ${message}`, ...args);
}
function logInfo(message: string, ...args: any[]) {
  log("INFO", message, ...args);
}
function logError(message: string, ...args: any[]) {
  log("ERROR", message, ...args);
}
function logDebug(message: string, ...args: any[]) {
  log("DEBUG", message, ...args);
}

// Notification utility
async function notify(message: string, title: string = "checklist") {
  console.log(`[${title}] ${message}`);
  try {
    await $`notify-send -t 3000 "${title}" "${message}"`.quiet();
  } catch {
    // Log error
    logError(`ERROR SENDING NOTIFICATION: [${title}] ${message}`);
  }
}

// Utility to check if a command exists
async function commandExists(cmd: string): Promise<boolean> {
  try {
    const result = await $`which ${cmd}`.quiet();
    return result.exitCode === 0;
  } catch {
    return false;
  }
}

// Get menu command (rofi preferred, fallback to wofi on Wayland)
async function getMenuCommand(): Promise<string[]> {
  if (await commandExists("rofi")) {
    return ["rofi", "-dmenu"];
  } else if (!!process.env.WAYLAND_DISPLAY && (await commandExists("wofi"))) {
    return ["wofi", "--show", "dmenu"];
  } else {
    throw new Error("Neither rofi nor wofi found.");
  }
}

// Helper to select from menu
async function selectOption(
  menuCommand: string[],
  options: string[],
  prompt: string,
  preselected = 0
): Promise<string> {
  if (options.length === 0) return "";
  try {
    const selected = (
      await $`printf '%s\n' ${options} | ${menuCommand} -p ${prompt} -selected-row ${preselected}`.text()
    ).trim();
    return selected;
  } catch (e) {
    // Rofi closed - exit programme
    console.log(e);
    process.exit(0);
  }
}

interface Task {
  name: string;
  done: boolean;
  timestamps: string[];
}

interface DayData {
  date: string;
  tasks: Task[];
}

async function main() {
  const checklistDir = process.env.CHECKLIST_DIR;
  if (!checklistDir) {
    await notify("CHECKLIST_DIR environment variable not set", "checklist");
    process.exit(1);
  }

  // Ensure directory exists
  if (!fs.existsSync(checklistDir)) {
    fs.mkdirSync(checklistDir, { recursive: true });
  }

  const dailyTasksPath = path.join(checklistDir, "daily_tasks.json");

  // Initialize daily_tasks.json if it doesn't exist
  if (!fs.existsSync(dailyTasksPath)) {
    const defaultTasks = [
      "Brush teeth in morning",
      "Brush teeth in evening",
      "Gym/pull-up bar",
      "Running",
      "Shower",
      "Wear cologne",
      "Productive day - got stuff done",
      "Free from distactions - no gaming, doom-scrolling, etc.",
      "Watched latest update videos - e.g. Everything Elon Musk Said Today",
    ];
    fs.writeFileSync(dailyTasksPath, JSON.stringify(defaultTasks, null, 2));
    logInfo("Initialized daily_tasks.json with default tasks");
  }

  // Load daily tasks
  const dailyTasks: string[] = JSON.parse(
    fs.readFileSync(dailyTasksPath, "utf-8")
  );

  // Get today's date
  const today = new Date().toISOString().split("T")[0]!; // YYYY-MM-DD

  const daysDir = path.join(checklistDir, "days");
  if (!fs.existsSync(daysDir)) {
    fs.mkdirSync(daysDir, { recursive: true });
  }

  // Also initialise day before & day after
  // Yesterday in YYYY-MM-DD format (local timezone)
  const yesterday = new Date();
  yesterday.setDate(yesterday.getDate() - 1);
  const yesterdayStr = yesterday.toISOString().split("T")[0]!;
  // Tomorrow in YYYY-MM-DD format (local timezone)
  const tomorrow = new Date();
  tomorrow.setDate(tomorrow.getDate() + 1);
  const tomorrowStr = tomorrow.toISOString().split("T")[0]!;

  const todayPath = path.join(daysDir, `${today}.json`);
  const yesterdayPath = path.join(daysDir, `${today}.json`);
  const tomorrowPath = path.join(daysDir, `${today}.json`);

  for (const x of [todayPath, yesterdayPath, tomorrowPath]) {
    // Initialize the days' data if it doesn't exist
    if (!fs.existsSync(todayPath)) {
      const tasks: Task[] = dailyTasks.map((name) => ({
        name,
        done: false,
        timestamps: [],
      }));
      const dayData: DayData = {
        date: x,
        tasks,
      };
      fs.writeFileSync(x, JSON.stringify(dayData, null, 2));
      logInfo(`Initialized ${x}.json`);
    }
  }

  // Load today's data
  const dayData: DayData = JSON.parse(fs.readFileSync(todayPath, "utf-8"));

  const menuCommand = await getMenuCommand();

  let taskIndex: number = 0;

  // Main loop
  while (true) {
    // Build menu options
    const options: string[] = dayData.tasks.map((task) => {
      const check = task.done ? " " : " ";
      return `${check} ${task.name}`;
    });

    const selected = await selectOption(
      menuCommand,
      options,
      "Checklist",
      taskIndex || 0
    );
    console.log(`Selected: ${selected}`);

    if (!selected) {
      // No selection, exit
      break;
    }

    // Find the task
    taskIndex = options.map((x) => x.trim()).indexOf(selected.trim());
    if (taskIndex === -1) {
      await notify("Invalid selection", "checklist");
      continue;
    }

    const task = dayData.tasks[taskIndex];
    if (!task) {
      await notify("Task not found", "checklist");
      continue;
    }

    // Toggle done status
    task.done = !task.done;
    const timestamp = new Date().toISOString();
    task.timestamps.push(timestamp);

    // Save back
    fs.writeFileSync(todayPath, JSON.stringify(dayData, null, 2));

    const status = task.done ? "done" : "undone";
    process.env.NOTIFY_EVERYTIME === "true" &&
      (await notify(`Marked "${task.name}" as ${status}`, "checklist"));
    logInfo(`Toggled ${task.name} to ${status} at ${timestamp}`);
  }

  process.exit(0);
}

main().catch(async (error) => {
  console.error("Error:", error);
  await notify("An error occurred", "checklist");
  process.exit(1);
});
