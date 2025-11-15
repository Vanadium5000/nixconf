#!/usr/bin/env bun

// passmenu.ts - Bun.js TypeScript script for browsing and selecting passwords from password-store using rofi or wofi

import { $ } from "bun";

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

// Utility function to check if a command exists
async function commandExists(cmd: string): Promise<boolean> {
  try {
    logDebug(`Checking if command exists: ${cmd}`);
    const result = await $`which ${cmd}`.quiet();
    const exists = result.exitCode === 0;
    logDebug(`Command ${cmd} ${exists ? "found" : "not found"}`);
    return exists;
  } catch {
    logDebug(`Command ${cmd} not found (exception)`);
    return false;
  }
}

// Determine menu command with fallback logic
async function getMenuCommand(): Promise<string[]> {
  const isWayland = !!process.env.WAYLAND_DISPLAY;
  logDebug(`Detecting menu command. Wayland: ${isWayland}`);

  // User prefers rofi on Wayland, so check for rofi first
  if (await commandExists("rofi")) {
    logInfo("Using rofi for menu selection");
    return ["rofi", "-dmenu"];
  } else if (isWayland && (await commandExists("wofi"))) {
    logInfo("Using wofi for menu selection");
    return ["wofi", "--show", "dmenu"];
  } else {
    logError("Neither rofi nor wofi found. Please install one of them.");
    throw new Error("Neither rofi nor wofi found. Please install one of them.");
  }
}

// Determine copy command
async function getCopyCommand(): Promise<string[]> {
  const isWayland = !!process.env.WAYLAND_DISPLAY;
  logDebug(`Detecting copy command. Wayland: ${isWayland}`);

  if (isWayland && (await commandExists("wl-copy"))) {
    logInfo("Using wl-copy for clipboard operations");
    return ["wl-copy"];
  } else if (await commandExists("xclip")) {
    logInfo("Using xclip for clipboard operations");
    return ["xclip", "-selection", "clipboard"];
  } else {
    logError("Neither wl-copy nor xclip found. Please install one of them.");
    throw new Error(
      "Neither wl-copy nor xclip found. Please install one of them."
    );
  }
}

// Determine type command
async function getTypeCommand(): Promise<string[]> {
  const isWayland = !!process.env.WAYLAND_DISPLAY;
  logDebug(`Detecting type command. Wayland: ${isWayland}`);

  if (isWayland && (await commandExists("wtype"))) {
    logInfo("Using wtype for typing operations");
    return ["wtype"];
  } else if (await commandExists("xdotool")) {
    logInfo("Using xdotool for typing operations");
    return ["xdotool", "type", "--clearmodifiers"];
  } else if (await commandExists("ydotool")) {
    logInfo("Using ydotool for typing operations");
    return ["ydotool", "type", "--"];
  } else {
    logError(
      "Neither wtype, xdotool, nor ydotool found. Please install one of them."
    );
    throw new Error(
      "Neither wtype, xdotool, nor ydotool found. Please install one of them."
    );
  }
}

// Determine tab key command
async function getTabCommand(): Promise<string[]> {
  const isWayland = !!process.env.WAYLAND_DISPLAY;
  logDebug(`Detecting tab command. Wayland: ${isWayland}`);

  if (isWayland && (await commandExists("wtype"))) {
    logInfo("Using wtype for tab key operations");
    return ["wtype", "-k", "tab"];
  } else if (await commandExists("xdotool")) {
    logInfo("Using xdotool for tab key operations");
    return ["xdotool", "key", "Tab"];
  } else if (await commandExists("ydotool")) {
    logInfo("Using ydotool for tab key operations");
    return ["ydotool", "key", "15:1", "15:0"]; // Tab key code
  } else {
    logError("No suitable tool found for sending tab key.");
    throw new Error("No suitable tool found for sending tab key.");
  }
}

interface Options {
  autotype: boolean;
  squash: boolean;
  fileisuser: boolean;
  copyCmd: string[];
  typeCmd: string[];
}

async function main() {
  let args = Bun.argv.slice(2);
  let options: Options = {
    autotype: false,
    squash: false,
    fileisuser: false,
    copyCmd: [],
    typeCmd: [],
  };

  let i = 0;
  while (i < args.length) {
    const arg = args[i];
    if (arg === "-a" || arg === "--autotype") {
      options.autotype = true;
    } else if (arg === "-s" || arg === "--squash") {
      options.squash = true;
    } else if (arg === "-f" || arg === "--fileisuser") {
      options.fileisuser = true;
    } else if (arg === "-c" || arg === "--copy") {
      i++;
      const nextArg = args[i];
      options.copyCmd =
        i < args.length && nextArg !== undefined && !nextArg.startsWith("-")
          ? nextArg.split(" ")
          : await getCopyCommand();
    } else if (arg === "-t" || arg === "--type") {
      i++;
      const nextArg = args[i];
      options.typeCmd =
        i < args.length && nextArg !== undefined && !nextArg.startsWith("-")
          ? nextArg.split(" ")
          : await getTypeCommand();
    } else if (arg === "-h" || arg === "--help") {
      const defaultCopyCommand = await getCopyCommand();
      const defaultTypeCommand = await getTypeCommand();
      console.log(`
Usage: passmenu [options]

Options:
  -a, --autotype     Enable autotype option (username <tab> password)
  -c, --copy [cmd]   Copy to clipboard (default: ${defaultCopyCommand})
  -f, --fileisuser   Use password file name as username if not specified
  -s, --squash       Skip field selection if only password is present
  -t, --type [cmd]   Type the selection (default: ${defaultTypeCommand})
  -h, --help         Show this help message

Supports PASSWORD_STORE_DIR environment variable.
Supports OTP if pass-otp is installed and entry has otpauth://.
Detects available tools and uses appropriate commands for Wayland/X11.
      `);
      process.exit(0);
    } else {
      console.error(`Unknown option: ${arg}`);
      console.error("Use -h or --help for usage information.");
      process.exit(1);
    }
    i++;
  }

  // Determine action: prefer type if set or if autotype (since autotype requires typing)
  let action = "copy";
  let actionCmd = options.copyCmd || (await getCopyCommand());
  if (options.typeCmd || options.autotype) {
    action = "type";
    actionCmd = options.typeCmd || (await getTypeCommand());
  }
  logInfo(`Action mode: ${action}, command: ${actionCmd.join(" ")}`);

  const passDir =
    process.env.PASSWORD_STORE_DIR || `${process.env.HOME}/.password-store`;
  logInfo(`Using password store directory: ${passDir}`);

  // Check if password store exists
  try {
    await $`ls -la ${passDir}`;
    logDebug("Password store directory exists");
  } catch {
    logError(`Password store directory not found: ${passDir}`);
    console.error(`Password store directory not found: ${passDir}`);
    console.error(
      "Please set PASSWORD_STORE_DIR or ensure ~/.password-store exists."
    );
    process.exit(1);
  }

  // Get list of password entries
  let listOutput: string;
  try {
    logDebug("Listing password entries from store");
    listOutput =
      await $`find ${passDir} -type f -name '*.gpg' -printf '%P\\n' | sed 's/\\.gpg$//' | sort`.text();
    logDebug(`Found password entries: ${listOutput.trim().split("\n").length}`);
  } catch (error) {
    logError("Failed to list password entries", error);
    console.error("Failed to list password entries:", error);
    process.exit(1);
  }

  const entrySuffix = ".gpg";
  const entries = listOutput
    .trim()
    .split("\\n")
    .filter(Boolean)
    .map((item) =>
      item.endsWith(entrySuffix) ? item.slice(0, -entrySuffix.length) : item
    );
  if (entries.length === 0) {
    logError("No password entries found in password store");
    console.error("No password entries found in password store.");
    process.exit(1);
  }
  logInfo(`Found ${entries.length} password entries`);

  // Get menu command
  const menuCommand = await getMenuCommand();
  logDebug(`Menu command: ${menuCommand.join(" ")}`);

  // Show menu to select entry
  let selectEntryPrompt: string;
  try {
    logDebug("Showing password selection menu");
    selectEntryPrompt =
      await $`printf '%s\n' ${entries} | ${menuCommand} -p 'Select password:'`.text();
    logDebug(`Menu output received: ${selectEntryPrompt.trim() || "(empty)"}`);
  } catch (error) {
    logError("Failed to show password selection menu", error);
    console.error("Failed to show password selection menu:", error);
    process.exit(1);
  }

  const selected = selectEntryPrompt.trim();
  if (!selected) {
    logInfo("User cancelled password selection");
    process.exit(0);
  }
  logInfo(`Selected password entry: ${selected}`);

  // Get password content
  let content: string;
  try {
    logDebug(`Retrieving password content for: ${selected}`);
    content = await $`pass show ${selected}`.text();
    logDebug("Password content retrieved successfully");
  } catch (error) {
    logError(`Failed to retrieve password for ${selected}`, error);
    console.error(`Failed to retrieve password for ${selected}:`, error);
    process.exit(1);
  }

  const lines = content.trim().split("\n");
  if (lines.length === 0) {
    console.error(`No content found for password entry: ${selected}`);
    process.exit(1);
  }

  const password = lines[0]?.trim() || "";

  // Parse fields
  let fields: Record<string, string> = {};
  let hasOtpauth = false;
  for (let j = 1; j < lines.length; j++) {
    const line = lines[j]?.trim() || "";
    if (line.startsWith("otpauth://")) {
      hasOtpauth = true;
    } else if (line.includes(":")) {
      const parts = line.split(":");
      if (parts.length >= 2) {
        const keyPart = parts[0];
        if (keyPart !== undefined) {
          const key = keyPart.trim().toLowerCase();
          const value = parts.slice(1).join(":").trim();
          fields[key] = value;
        }
      }
    }
  }

  // Check for OTP support
  let hasOtp = false;
  if (hasOtpauth) {
    hasOtp = true; // Default to true, worst that happens is the user selects existing otp & it fails
    // try {
    //   logDebug("OTP auth found, checking for pass otp");
    //   hasOtp = !(await $`pass otp`.nothrow())
    //     .text()
    //     .trim()
    //     .includes("Usage: pass otp");
    //   logDebug(`OTP support: ${hasOtp ? "available" : "unavailable"}`);
    // } catch (e) {
    //   logDebug(`OTP: Running pass otp failed with exception, carring on`);
    //   logDebug(`OTP support: ${hasOtp ? "available" : "unavailable"}`);
    // }
  }

  // Add username from file if needed
  if (!fields["username"] && options.fileisuser) {
    fields["username"] = selected.split("/").pop() || "";
    logDebug(`Added username from filename: ${fields["username"]}`);
  }

  // Build field options
  let fieldOptions = ["password"];
  for (const key in fields) {
    fieldOptions.push(key);
  }
  if (hasOtp) {
    fieldOptions.push("otp");
  }
  if (options.autotype) {
    fieldOptions.push("autotype");
  }
  fieldOptions = [...new Set(fieldOptions)]; // Deduplicate
  logDebug(`Available field options: ${fieldOptions.join(", ")}`);

  // Squash if applicable
  let selectedField = "";
  if (options.squash && fieldOptions.length === 1 && !options.autotype) {
    selectedField = "password";
    logInfo("Squash mode: automatically selected password field");
  } else {
    let selectFieldPrompt: string;
    try {
      logDebug(
        `Showing field selection menu with options: ${fieldOptions.join(", ")}`
      );
      selectFieldPrompt =
        await $`printf '%s\n' ${fieldOptions} | ${menuCommand} -p 'Select field:'`.text();
      logDebug(`Field menu output: ${selectFieldPrompt.trim() || "(empty)"}`);
    } catch (error) {
      logError("Failed to show field selection menu", error);
      console.error("Failed to show field selection menu:", error);
      process.exit(1);
    }
    selectedField = selectFieldPrompt.trim();
  }
  if (!selectedField) {
    logInfo("User cancelled field selection");
    process.exit(0);
  }
  logInfo(`Selected field: ${selectedField}`);

  // Get value
  let value = "";
  if (selectedField === "password") {
    value = password;
    logDebug("Using password value");
  } else if (selectedField === "otp") {
    try {
      logDebug("Generating OTP for selected entry");
      value = (await $`pass otp ${selected}`.text()).trim();
      logDebug("OTP generated successfully");
    } catch (error) {
      logError(`Failed to generate OTP for ${selected}`, error);
      console.error(`Failed to generate OTP for ${selected}:`, error);
      process.exit(1);
    }
  } else if (selectedField === "autotype") {
    // Autotype handled below
    logDebug("Autotype mode selected");
  } else {
    value = fields[selectedField] || "";
    logDebug(`Using field value for: ${selectedField}`);
  }

  // Perform action
  try {
    logInfo(`Performing ${action} action with field: ${selectedField}`);
    if (selectedField === "autotype") {
      const username = fields["username"] || "";
      logDebug(`Autotype: username=${!!username}, password=${!!password}`);
      if (action === "type") {
        if (username) {
          logDebug("Typing username");
          await $`echo -n ${username} | xargs ${actionCmd}`;
          const tabCmd = await getTabCommand();
          logDebug("Sending tab key");
          await $`${tabCmd}`;
        }
        logDebug("Typing password");
        await $`echo -n ${password} | xargs ${actionCmd}`;
      } else {
        // If copy mode, copy password (fallback)
        logDebug("Copying password (autotype fallback)");
        await $`echo -n ${password} | xargs ${actionCmd}`;
      }
    } else {
      logDebug(`Executing action command: ${actionCmd.join(" ")}`);
      await $`echo -n ${value} | xargs ${actionCmd}`;
    }
    logInfo("Action completed successfully");
  } catch (error) {
    logError(
      `Failed to perform action (${action}) with command: ${actionCmd.join(
        " "
      )}`,
      error
    );
    console.error(
      `Failed to perform action (${action}) with command: ${actionCmd}`,
      error
    );
    process.exit(1);
  }
}

// Run main function with error handling
logInfo("Starting passmenu script");
main().catch((error) => {
  logError("An unexpected error occurred", error);
  console.error("An unexpected error occurred:", error);
  process.exit(1);
});
