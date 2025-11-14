#!/usr/bin/env bun

// passmenu.ts - Bun.js TypeScript script for browsing and selecting passwords from password-store using rofi or wofi

import { $ } from "bun";

const isWayland = !!process.env.WAYLAND_DISPLAY;

const menuCommand = isWayland ? "wofi --show dmenu" : "rofi -dmenu";
const defaultCopyCommand = isWayland ? "wl-copy" : "xclip -selection clipboard";
const defaultTypeCommand = isWayland
  ? "wtype"
  : "xdotool type --clearmodifiers";

let args = Bun.argv.slice(2);
let options: {
  autotype: boolean;
  squash: boolean;
  fileisuser: boolean;
  copyCmd: string;
  typeCmd: string;
} = {
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
    options.copyCmd =
      i < args.length && !args[i].startsWith("-")
        ? args[i]
        : defaultCopyCommand;
  } else if (arg === "-t" || arg === "--type") {
    i++;
    options.typeCmd =
      i < args.length && !args[i].startsWith("-")
        ? args[i]
        : defaultTypeCommand;
  } else if (arg === "-h" || arg === "--help") {
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
Detects Wayland for wofi/wtype/wl-copy or X11 for rofi/xdotool/xclip.
    `);
    process.exit(0);
  }
  i++;
}

// Determine action: prefer type if set or if autotype (since autotype requires typing)
let action = "copy";
let actionCmd = options.copyCmd || defaultCopyCommand;
if (options.typeCmd || options.autotype) {
  action = "type";
  actionCmd = options.typeCmd || defaultTypeCommand;
}

const passDir =
  process.env.PASSWORD_STORE_DIR || `${process.env.HOME}/.password-store`;

// Get list of password entries
let listOutput =
  await $`find ${passDir} -type f -name '*.gpg' -printf '%P\\n' | sed 's/\\.gpg$//' | sort`.text();
const entries = listOutput.trim().split("\n").filter(Boolean);

// Show menu to select entry
const selectEntryPrompt = await $`echo -e ${entries.join(
  "\\n"
)} | ${menuCommand} -p 'Select password:'`.text();
const selected = selectEntryPrompt.trim();
if (!selected) process.exit(0);

// Get password content
const content = await $`pass show ${selected}`.text();
const lines = content.trim().split("\n");
const password = lines[0].trim();

// Parse fields
let fields: Record<string, string> = {};
let hasOtpauth = false;
for (let j = 1; j < lines.length; j++) {
  const line = lines[j].trim();
  if (line.startsWith("otpauth://")) {
    hasOtpauth = true;
  } else if (line.includes(":")) {
    const [key, ...valueParts] = line.split(":");
    const value = valueParts.join(":").trim();
    fields[key.trim().toLowerCase()] = value;
  }
}

// Check for OTP support
let hasOtp = false;
if (hasOtpauth) {
  const otpCheck = await $`command -v pass-otp`.quiet();
  if (otpCheck.exitCode === 0) {
    hasOtp = true;
  }
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
fieldOptions = [...new Set(fieldOptions)]; // Deduplicate if any

// Squash if applicable
let selectedField = "";
if (options.squash && fieldOptions.length === 1 && !options.autotype) {
  selectedField = "password";
} else {
  const selectFieldPrompt = await $`echo -e ${fieldOptions.join(
    "\\n"
  )} | ${menuCommand} -p 'Select field:'`.text();
  selectedField = selectFieldPrompt.trim();
}
if (!selectedField) process.exit(0);

// Get value
let value = "";
if (selectedField === "password") {
  value = password;
} else if (selectedField === "otp") {
  value = await $`pass otp ${selected}`.text().trim();
} else if (selectedField === "autotype") {
  // Autotype handled below
} else {
  value = fields[selectedField] || "";
}

// Perform action
if (selectedField === "autotype") {
  const username = fields["username"] || "";
  if (action === "type") {
    if (username) {
      await $`echo -n ${username} | ${actionCmd}`;
      if (isWayland) {
        await $`wtype -k tab`;
      } else {
        await $`xdotool key Tab`;
      }
    }
    await $`echo -n ${password} | ${actionCmd}`;
  } else {
    // If copy mode, perhaps copy password (fallback)
    await $`echo -n ${password} | ${actionCmd}`;
  }
} else {
  await $`echo -n ${value} | ${actionCmd}`;
}
