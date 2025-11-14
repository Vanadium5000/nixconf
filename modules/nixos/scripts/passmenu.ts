#!/usr/bin/env bun

// passmenu.ts - Bun.js TypeScript script for browsing and selecting passwords from password-store using rofi or wofi

import { $ } from "bun";

// Utility function to check if a command exists
async function commandExists(cmd: string): Promise<boolean> {
  try {
    const result = await $`which ${cmd}`.quiet();
    return result.exitCode === 0;
  } catch {
    return false;
  }
}

// Determine menu command with fallback logic
async function getMenuCommand(): Promise<string> {
  const isWayland = !!process.env.WAYLAND_DISPLAY;

  // User prefers rofi on Wayland, so check for rofi first
  if (await commandExists("rofi")) {
    return "rofi -dmenu";
  } else if (isWayland && (await commandExists("wofi"))) {
    return "wofi --show dmenu";
  } else {
    throw new Error("Neither rofi nor wofi found. Please install one of them.");
  }
}

// Determine copy command
async function getCopyCommand(): Promise<string> {
  const isWayland = !!process.env.WAYLAND_DISPLAY;

  if (isWayland && (await commandExists("wl-copy"))) {
    return "wl-copy";
  } else if (await commandExists("xclip")) {
    return "xclip -selection clipboard";
  } else {
    throw new Error(
      "Neither wl-copy nor xclip found. Please install one of them."
    );
  }
}

// Determine type command
async function getTypeCommand(): Promise<string> {
  const isWayland = !!process.env.WAYLAND_DISPLAY;

  if (isWayland && (await commandExists("wtype"))) {
    return "wtype";
  } else if (await commandExists("xdotool")) {
    return "xdotool type --clearmodifiers";
  } else if (await commandExists("ydotool")) {
    return "ydotool type --";
  } else {
    throw new Error(
      "Neither wtype, xdotool, nor ydotool found. Please install one of them."
    );
  }
}

// Determine tab key command
async function getTabCommand(): Promise<string> {
  const isWayland = !!process.env.WAYLAND_DISPLAY;

  if (isWayland && (await commandExists("wtype"))) {
    return "wtype -k tab";
  } else if (await commandExists("xdotool")) {
    return "xdotool key Tab";
  } else if (await commandExists("ydotool")) {
    return "ydotool key 15:1 15:0"; // Tab key code
  } else {
    throw new Error("No suitable tool found for sending tab key.");
  }
}

interface Options {
  autotype: boolean;
  squash: boolean;
  fileisuser: boolean;
  copyCmd: string;
  typeCmd: string;
}

async function main() {
  let args = Bun.argv.slice(2);
  let options: Options = {
    autotype: false,
    squash: false,
    fileisuser: false,
    copyCmd: "",
    typeCmd: "",
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
          ? nextArg
          : await getCopyCommand();
    } else if (arg === "-t" || arg === "--type") {
      i++;
      const nextArg = args[i];
      options.typeCmd =
        i < args.length && nextArg !== undefined && !nextArg.startsWith("-")
          ? nextArg
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

  const passDir =
    process.env.PASSWORD_STORE_DIR || `${process.env.HOME}/.password-store`;

  // Check if password store exists
  try {
    await $`ls -la ${passDir} >/dev/null 2>&1`;
  } catch {
    console.error(`Password store directory not found: ${passDir}`);
    console.error(
      "Please set PASSWORD_STORE_DIR or ensure ~/.password-store exists."
    );
    process.exit(1);
  }

  // Get list of password entries
  let listOutput: string;
  try {
    listOutput =
      await $`find ${passDir} -type f -name '*.gpg' -printf '%P\\n' | sed 's/\\.gpg$//' | sort`.text();
  } catch (error) {
    console.error("Failed to list password entries:", error);
    process.exit(1);
  }

  const entries = listOutput.trim().split("\n").filter(Boolean);
  if (entries.length === 0) {
    console.error("No password entries found in password store.");
    process.exit(1);
  }

  // Get menu command
  const menuCommand = await getMenuCommand();

  // Show menu to select entry
  let selectEntryPrompt: string;
  try {
    selectEntryPrompt = await $`echo -e ${entries.join(
      "\\n"
    )} | ${menuCommand} -p 'Select password:'`.text();
  } catch (error) {
    console.error("Failed to show password selection menu:", error);
    process.exit(1);
  }

  const selected = selectEntryPrompt.trim();
  if (!selected) process.exit(0);

  // Get password content
  let content: string;
  try {
    content = await $`pass show ${selected}`.text();
  } catch (error) {
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
    hasOtp = await commandExists("pass-otp");
  }

  // Add username from file if needed
  if (!fields["username"] && options.fileisuser) {
    fields["username"] = selected.split("/").pop() || "";
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

  // Squash if applicable
  let selectedField = "";
  if (options.squash && fieldOptions.length === 1 && !options.autotype) {
    selectedField = "password";
  } else {
    let selectFieldPrompt: string;
    try {
      selectFieldPrompt = await $`echo -e ${fieldOptions.join(
        "\\n"
      )} | ${menuCommand} -p 'Select field:'`.text();
    } catch (error) {
      console.error("Failed to show field selection menu:", error);
      process.exit(1);
    }
    selectedField = selectFieldPrompt.trim();
  }
  if (!selectedField) process.exit(0);

  // Get value
  let value = "";
  if (selectedField === "password") {
    value = password;
  } else if (selectedField === "otp") {
    try {
      value = (await $`pass otp ${selected}`.text()).trim();
    } catch (error) {
      console.error(`Failed to generate OTP for ${selected}:`, error);
      process.exit(1);
    }
  } else if (selectedField === "autotype") {
    // Autotype handled below
  } else {
    value = fields[selectedField] || "";
  }

  // Perform action
  try {
    if (selectedField === "autotype") {
      const username = fields["username"] || "";
      if (action === "type") {
        if (username) {
          await $`echo -n ${username} | ${actionCmd}`;
          const tabCmd = await getTabCommand();
          await $`${tabCmd}`;
        }
        await $`echo -n ${password} | ${actionCmd}`;
      } else {
        // If copy mode, copy password (fallback)
        await $`echo -n ${password} | ${actionCmd}`;
      }
    } else {
      await $`echo -n ${value} | ${actionCmd}`;
    }
  } catch (error) {
    console.error(
      `Failed to perform action (${action}) with command: ${actionCmd}`,
      error
    );
    process.exit(1);
  }
}

// Run main function with error handling
main().catch((error) => {
  console.error("An unexpected error occurred:", error);
  process.exit(1);
});
