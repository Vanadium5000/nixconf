#!/usr/bin/env bun
import { readdir, readFile } from "fs/promises";
import { join, basename } from "path";
import { homedir } from "os";

const SEARCH_PATHS = [
  "/run/current-system/sw/share/applications",
  join(homedir(), ".nix-profile/share/applications"),
  join(homedir(), ".local/share/applications"),
  "/usr/share/applications",
];

interface DesktopAction {
  name: string;
  exec: string;
}

interface DesktopEntry {
  name: string;
  exec: string;
  icon: string;
  actions: DesktopAction[];
}

function parseDesktopFile(content: string): DesktopEntry | null {
  const lines = content.split("\n");
  const entry: Record<string, string> = {};
  const actions: Map<string, DesktopAction> = new Map();
  let currentSection = "";
  let currentActionId = "";

  for (const line of lines) {
    const trimmed = line.trim();
    
    if (trimmed.startsWith("[")) {
      currentSection = trimmed;
      if (trimmed.startsWith("[Desktop Action ")) {
        currentActionId = trimmed.slice(16, -1);
        actions.set(currentActionId, { name: "", exec: "" });
      }
      continue;
    }

    if (!trimmed.includes("=")) continue;
    const [key, ...rest] = trimmed.split("=");
    const value = rest.join("=");

    if (currentSection === "[Desktop Entry]") {
      entry[key.trim()] = value.trim();
    } else if (currentSection.startsWith("[Desktop Action ") && currentActionId) {
      const action = actions.get(currentActionId);
      if (action) {
        if (key.trim() === "Name") action.name = value.trim();
        if (key.trim() === "Exec") action.exec = value.trim().replace(/%[fFuUikcdDnNvm]/g, "").trim();
      }
    }
  }

  if (entry["NoDisplay"] === "true") return null;
  if (entry["Type"] !== "Application") return null;
  if (!entry["Name"] || !entry["Exec"]) return null;

  const execCmd = entry["Exec"].replace(/%[fFuUikcdDnNvm]/g, "").trim();
  
  const actionList: DesktopAction[] = [];
  const actionIds = entry["Actions"]?.split(";").filter(Boolean) || [];
  for (const id of actionIds) {
    const action = actions.get(id);
    if (action?.name && action?.exec) {
      actionList.push(action);
    }
  }

  return {
    name: entry["Name"],
    exec: execCmd,
    icon: entry["Icon"] || "",
    actions: actionList,
  };
}

async function loadApps(): Promise<DesktopEntry[]> {
  const seen = new Set<string>();
  const apps: DesktopEntry[] = [];

  for (const dir of SEARCH_PATHS) {
    try {
      const files = await readdir(dir);
      const desktopFiles = files.filter(f => f.endsWith(".desktop"));
      
      const entries = await Promise.all(
        desktopFiles.map(async (file) => {
          try {
            const content = await readFile(join(dir, file), "utf-8");
            return parseDesktopFile(content);
          } catch {
            return null;
          }
        })
      );

      for (const entry of entries) {
        if (entry && !seen.has(entry.name)) {
          seen.add(entry.name);
          apps.push(entry);
        }
      }
    } catch {
      continue;
    }
  }

  return apps.sort((a, b) => a.name.toLowerCase().localeCompare(b.name.toLowerCase()));
}

const apps = await loadApps();
const output = apps.map(app => {
  const actionsJson = JSON.stringify(app.actions);
  return `${app.name}\t${app.exec}\t${app.icon}\t${actionsJson}`;
});
console.log(output.join("\n"));
