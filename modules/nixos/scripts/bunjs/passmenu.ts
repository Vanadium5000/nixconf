#!/usr/bin/env bun
/**
 * passmenu.ts - Password store browser using qs-dmenu
 *
 * Features:
 * - Browse and select passwords from pass (password-store)
 * - Generate credentials (passwords, usernames, emails)
 * - Temporary email management via mail.tm API
 * - TOTP support with QR code scanning
 * - Autotype with keyboard simulation
 * - 60-second state persistence for quick re-access
 */

import { $ } from "bun";
import { faker } from "@faker-js/faker";
import crypto from "node:crypto";
import { join } from "path";
import { existsSync, mkdirSync } from "fs";

// =============================================================================
// Constants & Configuration
// =============================================================================

const STATE_DIR = join(process.env.HOME || "", ".cache", "passmenu");
const STATE_FILE = join(STATE_DIR, "state.json");
const STATE_EXPIRY_MS = 60_000; // 60 seconds

/** Fields that represent username-type values (used for autotype fallback) */
const USERNAME_FIELD_ALIASES = ["login", "user", "username"] as const;

/**
 * Fixed display order for credential fields.
 * Fields appear in this order, with other fields after these, before OTP.
 * "username (from path)" always appears alongside explicit username fields.
 */
const FIELD_DISPLAY_ORDER = [
  "username",
  "login",
  "user",
  "username (from path)",
  "email",
  "password",
] as const;

/** Prefix for temp email fields in the field options menu */
const TEMP_EMAIL_FIELD_PREFIX = "email (from temp emails)" as const;

/** Special menu entries in main menu */
const SPECIAL_ENTRIES = [
  "Generate Credential",
  "Manage Temp Emails",
  "Create Credential",
] as const;

// =============================================================================
// Types
// =============================================================================

interface State {
  timestamp: number;
  lastEntry?: string;
  lastField?: string;
}

interface Options {
  autotype: boolean;
  squash: boolean;
  fileisuser: boolean;
  copyCmd?: string[];
  typeCmd?: string[];
}

interface ParsedCredential {
  password: string;
  fields: Record<string, string>;
  hasOtpauth: boolean;
}

interface TempEmail {
  path: string;
  email: string;
  associated: string;
  display: string;
}

// =============================================================================
// Logging & Notifications
// =============================================================================

function log(level: string, message: string, ...args: unknown[]): void {
  const timestamp = new Date().toISOString();
  console.log(`[${timestamp}] [${level}] ${message}`, ...args);
}

const logInfo = (message: string, ...args: unknown[]) =>
  log("INFO", message, ...args);
const logError = (message: string, ...args: unknown[]) =>
  log("ERROR", message, ...args);
const logDebug = (message: string, ...args: unknown[]) =>
  log("DEBUG", message, ...args);

async function notify(
  message: string,
  title: string = "passmenu"
): Promise<void> {
  console.log(`[${title}] ${message}`);
  try {
    await $`notify-send -t 3000 ${title} ${message}`.quiet();
  } catch {
    logError(`Failed to send notification: [${title}] ${message}`);
  }
}

// =============================================================================
// Command Detection
// =============================================================================

async function commandExists(cmd: string): Promise<boolean> {
  try {
    const result = await $`which ${cmd}`.quiet();
    return result.exitCode === 0;
  } catch {
    return false;
  }
}

async function getMenuCommand(): Promise<string[]> {
  if (await commandExists("qs-dmenu")) {
    return ["qs-dmenu"];
  }
  if (process.env.WAYLAND_DISPLAY && (await commandExists("wofi"))) {
    return ["wofi", "--show", "dmenu"];
  }
  throw new Error("qs-dmenu not found.");
}

async function getCopyCommand(): Promise<string[]> {
  if (process.env.WAYLAND_DISPLAY && (await commandExists("wl-copy"))) {
    return ["wl-copy", "--type", "text/plain"];
  }
  if (await commandExists("xclip")) {
    return ["xclip", "-selection", "clipboard"];
  }
  throw new Error("Neither wl-copy nor xclip found.");
}

async function getTypeCommand(): Promise<string[]> {
  if (process.env.WAYLAND_DISPLAY && (await commandExists("wtype"))) {
    return ["wtype"];
  }
  if (await commandExists("xdotool")) {
    return ["xdotool", "type", "--clearmodifiers"];
  }
  if (await commandExists("ydotool")) {
    return ["ydotool", "type", "--"];
  }
  throw new Error("Neither wtype, xdotool, nor ydotool found.");
}

async function getTabCommand(): Promise<string[]> {
  if (process.env.WAYLAND_DISPLAY && (await commandExists("wtype"))) {
    return ["wtype", "-k", "tab"];
  }
  if (await commandExists("xdotool")) {
    return ["xdotool", "key", "Tab"];
  }
  if (await commandExists("ydotool")) {
    return ["ydotool", "key", "15:1", "15:0"];
  }
  throw new Error("No tool found for tab key.");
}

// =============================================================================
// State Management
// =============================================================================

async function loadState(): Promise<State> {
  if (!existsSync(STATE_FILE)) {
    return { timestamp: 0 };
  }
  try {
    return await Bun.file(STATE_FILE).json();
  } catch {
    return { timestamp: 0 };
  }
}

async function saveState(state: Partial<State>): Promise<void> {
  if (!existsSync(STATE_DIR)) {
    mkdirSync(STATE_DIR, { recursive: true });
  }
  const current = await loadState();
  const newState = { ...current, ...state, timestamp: Date.now() };
  await Bun.write(STATE_FILE, JSON.stringify(newState));
}

async function clearState(): Promise<void> {
  if (existsSync(STATE_FILE)) {
    await Bun.write(STATE_FILE, JSON.stringify({ timestamp: 0 }));
  }
}

function isStateRecent(state: State): boolean {
  return Date.now() - state.timestamp < STATE_EXPIRY_MS;
}

// =============================================================================
// Menu Helpers
// =============================================================================

/**
 * Display a menu and return the selected option
 * @param initialIndex - 0-based index to pre-select
 */
async function selectOption(
  menuCommand: string[],
  options: string[],
  prompt: string,
  initialIndex?: number
): Promise<string> {
  if (options.length === 0) return "";

  const cmd = [...menuCommand];

  // Pass selection index via environment variable for dmenu.qml
  const env = { ...process.env };
  if (initialIndex !== undefined && initialIndex >= 0) {
    env["DMENU_SELECTED"] = initialIndex.toString();
  }

  try {
    const result = await $`printf '%s\n' ${options} | ${cmd} -p ${prompt}`
      .env(env)
      .nothrow()
      .quiet();

    if (result.exitCode !== 0) return "";
    return result.text().trim();
  } catch {
    return "";
  }
}

// =============================================================================
// Clipboard & Typing Actions
// =============================================================================

async function performAction(
  value: string,
  action: "copy" | "type",
  actionCmd: string[]
): Promise<void> {
  const proc = Bun.spawn(actionCmd, { stdin: "pipe" });
  proc.stdin.write(value);
  proc.stdin.end();
  await proc.exited;
}

// =============================================================================
// Credential Parsing
// =============================================================================

/**
 * Parse pass entry content into structured credential data
 * Handles both standard format (password on first line) and key:value format
 */
function parseCredential(content: string, entryPath: string): ParsedCredential {
  const lines = content.trim().split("\n");
  let password = "";
  const fields: Record<string, string> = {};
  let hasOtpauth = false;

  // Check if first line is a key:value pair
  const firstLineIsKeyValue = lines[0]?.includes(":");

  if (firstLineIsKeyValue) {
    // All lines are key:value pairs
    for (const line of lines) {
      const trimmed = line.trim();
      if (trimmed.startsWith("otpauth://")) {
        hasOtpauth = true;
        continue;
      }
      if (trimmed.includes(":")) {
        const colonIdx = trimmed.indexOf(":");
        const key = trimmed.slice(0, colonIdx).trim().toLowerCase();
        const value = trimmed.slice(colonIdx + 1).trim();
        if (key === "password") {
          password = value;
        } else {
          fields[key] = value;
        }
      }
    }
  } else {
    // Standard pass format: first line is password
    password = lines[0]?.trim() || "";
    for (let i = 1; i < lines.length; i++) {
      const line = lines[i]?.trim() || "";
      if (line.startsWith("otpauth://")) {
        hasOtpauth = true;
        continue;
      }
      if (line.includes(":")) {
        const colonIdx = line.indexOf(":");
        const key = line.slice(0, colonIdx).trim().toLowerCase();
        const value = line.slice(colonIdx + 1).trim();
        fields[key] = value;
      }
    }
  }

  // Always add username derived from path, regardless of other username fields
  const filename = entryPath.split("/").pop();
  if (filename) {
    fields["username (from path)"] = filename;
  }

  return { password, fields, hasOtpauth };
}

/**
 * Build ordered field options for display
 * Order: [credential path], username, password, [other fields...], otp, autotype
 */
function buildFieldOptions(
  credential: ParsedCredential,
  entryPath: string,
  showAutotype: boolean
): string[] {
  const options: string[] = [];

  // First entry: credential path (for edit options)
  options.push(`📁 ${entryPath}`);

  // Fixed order fields first
  for (const field of FIELD_DISPLAY_ORDER) {
    if (field === "password" && credential.password) {
      options.push("password");
    } else if (credential.fields[field]) {
      options.push(field);
    }
  }

  // Other fields (excluding those already added and username aliases)
  const excludeFields = new Set([
    ...FIELD_DISPLAY_ORDER,
    ...USERNAME_FIELD_ALIASES,
  ]);
  const otherFields = Object.keys(credential.fields)
    .filter(
      (f) => !excludeFields.has(f as "username" | "password" | "login" | "user")
    )
    .sort();
  options.push(...otherFields);

  // OTP at the end (before autotype)
  if (credential.hasOtpauth) {
    options.push("otp");
  }

  // Autotype last
  if (showAutotype) {
    options.push("autotype");
  }

  return options;
}

// =============================================================================
// Credential Generators
// =============================================================================

/**
 * Generate alphanumeric-only username (no underscores or special chars).
 * Pattern: adjective + noun + digits (e.g., "swiftblade42")
 */
function generateAlphanumericUsername(): string {
  // Use faker words but strip non-alphanumeric characters
  const adj = faker.word
    .adjective()
    .replace(/[^a-z]/gi, "")
    .toLowerCase();
  const noun = faker.word
    .noun()
    .replace(/[^a-z]/gi, "")
    .toLowerCase();
  const num = faker.number.int({ min: 1, max: 99 });
  return `${adj}${noun}${num}`;
}

/**
 * Generate username from a full name.
 * Pattern: normalized name + digits (e.g., "johnsmith42")
 */
function generateUsernameFromName(fullName: string): string {
  const base = fullName.toLowerCase().replace(/[^a-z0-9]/g, "");
  const num = faker.number.int({ min: 1, max: 99 });
  return `${base}${num}`;
}

const credentialGenerators: Record<string, () => string> = {
  password: () => crypto.randomBytes(32).toString("base64"),
  "password (small)": () => crypto.randomBytes(15).toString("base64"),
  username: generateAlphanumericUsername,
  "full name": () => faker.person.fullName(),
  "phone number": () => faker.phone.number({ style: "international" }),
  "lorem ipsum": () => faker.lorem.paragraph(),
  "US address": () => {
    // Full comma-separated US address format
    const street = faker.location.streetAddress();
    const city = faker.location.city();
    const state = faker.location.state({ abbreviated: false });
    const zip = faker.location.zipCode();
    return `${street}, ${city}, ${state} ${zip}`;
  },
};

function generateFakeEmail(): string {
  return faker.internet.email();
}

// =============================================================================
// Pass Store Operations
// =============================================================================

/**
 * Find all temporary emails associated with a given credential path.
 * Temp emails are stored at: temp_emails/<associated_path>/<email_address>
 */
async function findAssociatedTempEmails(
  passDir: string,
  entryPath: string
): Promise<string[]> {
  if (!entryPath || entryPath.startsWith("temp_emails/")) {
    return [];
  }

  const tempEmailPath = join(passDir, "temp_emails", entryPath);

  try {
    const result =
      await $`find ${tempEmailPath} -maxdepth 1 -type f -name '*.gpg' -printf '%f\n' 2>/dev/null`
        .nothrow()
        .quiet()
        .text();

    if (!result.trim()) {
      return [];
    }

    return result
      .trim()
      .split("\n")
      .filter(Boolean)
      .map((filename) => filename.replace(/\.gpg$/, ""));
  } catch {
    return [];
  }
}

async function appendToPass(
  path: string,
  field: string,
  value: string
): Promise<void> {
  const existing = await $`pass show ${path}`.text().catch(() => "");
  const lines = existing.trim().split("\n").filter(Boolean);

  if (field === "password") {
    lines.unshift(value);
  } else {
    lines.push(`${field}: ${value}`);
  }

  const content = lines.join("\n") + "\n";
  await $`echo ${content} | pass insert --multiline --force ${path}`;
}

async function listPassEntries(passDir: string): Promise<string[]> {
  const listOutput =
    await $`find ${passDir} -type f -name '*.gpg' -printf '%P\n'`.text();
  return listOutput
    .trim()
    .split("\n")
    .filter(Boolean)
    .map((entry) => entry.replace(/\.gpg$/, ""))
    .filter((e) => !e.startsWith("temp_emails/"))
    .sort();
}

// =============================================================================
// Edit Operations
// =============================================================================

/**
 * Scan QR code for TOTP and add to credential
 * Uses grim + slurp + zbar on Wayland
 */
async function addTotpFromQr(entryPath: string): Promise<boolean> {
  try {
    // Capture QR code region and decode
    const result =
      await $`grim -g "$(slurp -d)" - | zbarimg -q --raw - 2>/dev/null`
        .nothrow()
        .text();

    const otpUri = result.trim();
    if (!otpUri.startsWith("otpauth://")) {
      await notify("No valid TOTP QR code detected", "passmenu");
      return false;
    }

    // Append to pass entry
    const existing = await $`pass show ${entryPath}`.text().catch(() => "");
    const content = existing.trim() + "\n" + otpUri + "\n";
    await $`echo ${content} | pass insert --multiline --force ${entryPath}`;

    await notify("TOTP added successfully", "passmenu");
    return true;
  } catch (error) {
    logError("Failed to add TOTP from QR", error);
    await notify("Failed to scan QR code", "passmenu");
    return false;
  }
}

async function hasTerminal(): Promise<boolean> {
  return !!process.env.TERM && process.env.TERM !== "dumb";
}

async function getTerminalCommand(): Promise<string[]> {
  if (await commandExists("kitty")) {
    return ["kitty", "--"];
  }
  if (await commandExists("alacritty")) {
    return ["alacritty", "-e"];
  }
  if (await commandExists("foot")) {
    return ["foot", "--"];
  }
  if (await commandExists("wezterm")) {
    return ["wezterm", "start", "--"];
  }
  throw new Error("No terminal emulator found");
}

async function editCredential(entryPath: string): Promise<void> {
  try {
    if (await hasTerminal()) {
      const proc = Bun.spawn(["pass", "edit", entryPath], {
        stdin: "inherit",
        stdout: "inherit",
        stderr: "inherit",
        env: { ...process.env },
      });
      await proc.exited;
    } else {
      const termCmd = await getTerminalCommand();
      const proc = Bun.spawn([...termCmd, "pass", "edit", entryPath], {
        stdin: "inherit",
        stdout: "inherit",
        stderr: "inherit",
        env: { ...process.env },
      });
      await proc.exited;
    }
  } catch (error) {
    logError("Failed to edit credential", error);
    await notify("Failed to open editor", "passmenu");
  }
}

async function deleteCredential(
  menuCommand: string[],
  entryPath: string
): Promise<boolean> {
  const confirm = await selectOption(
    menuCommand,
    ["No, keep it", "Yes, delete permanently"],
    `Delete ${entryPath}?`
  );

  if (confirm === "Yes, delete permanently") {
    try {
      await $`pass rm -f ${entryPath}`.quiet();
      await notify(`Deleted: ${entryPath}`, "passmenu");
      return true;
    } catch (error) {
      logError("Failed to delete credential", error);
      await notify("Failed to delete credential", "passmenu");
      return false;
    }
  }
  return false;
}

/**
 * Show edit options menu for a credential
 */
async function showEditOptions(
  menuCommand: string[],
  entryPath: string,
  passDir: string
): Promise<"back" | "exit" | "deleted" | "moved"> {
  const options = [
    "← Back",
    "📷 Add TOTP from QR Code",
    "✏️ Edit with $EDITOR",
    "📦 Move Credential",
    "🗑️ Delete Credential",
  ];

  const selected = await selectOption(
    menuCommand,
    options,
    `Edit: ${entryPath}`
  );

  switch (selected) {
    case "← Back":
    case "":
      return "back";
    case "📷 Add TOTP from QR Code":
      await addTotpFromQr(entryPath);
      return "back";
    case "✏️ Edit with $EDITOR":
      await editCredential(entryPath);
      return "exit";
    case "📦 Move Credential": {
      // Check for associated temp emails first
      const tempEmailPath = join(passDir, "temp_emails", entryPath);
      let hasTempEmails = false;
      try {
        const result =
          await $`find ${tempEmailPath} -maxdepth 1 -type f -name '*.gpg' 2>/dev/null`
            .nothrow()
            .quiet()
            .text();
        hasTempEmails = result.trim().length > 0;
      } catch {
        // No temp emails directory
      }

      if (hasTempEmails) {
        const proceed = await selectOption(
          menuCommand,
          ["Cancel", "Move anyway (temp emails will be orphaned)"],
          "This credential has associated temp emails"
        );
        if (proceed !== "Move anyway (temp emails will be orphaned)") {
          return "back";
        }
      }

      const newPath = (
        await $`echo -n | ${menuCommand} -p 'Enter new path:'`.text()
      ).trim();

      // Validate path
      if (!newPath) {
        return "back";
      }
      if (newPath === entryPath) {
        await notify("New path is same as current", "passmenu");
        return "back";
      }

      // Check target doesn't exist
      try {
        await $`pass show ${newPath}`.quiet();
        await notify("Target path already exists", "passmenu");
        return "back";
      } catch {
        // Good, target doesn't exist
      }

      try {
        await $`pass mv -f ${entryPath} ${newPath}`.quiet();
        await notify(`Moved to: ${newPath}`, "passmenu");
        return "moved";
      } catch (error) {
        logError("Failed to move credential", error);
        await notify("Failed to move credential", "passmenu");
        return "back";
      }
    }
    case "🗑️ Delete Credential":
      const deleted = await deleteCredential(menuCommand, entryPath);
      return deleted ? "deleted" : "back";
    default:
      return "back";
  }
}

// =============================================================================
// Create Credential
// =============================================================================

async function createCredential(
  menuCommand: string[],
  passDir: string
): Promise<void> {
  // Prompt for path
  const path = (
    await $`echo -n | ${menuCommand} -p 'Enter credential path (e.g., personal/site/account)'`.text()
  ).trim();

  if (!path) {
    await notify("No path entered", "passmenu");
    return;
  }

  // Check if already exists
  try {
    await $`pass show ${path}`.quiet();
    await notify("Credential already exists", "passmenu");
    return;
  } catch {
    // Good, doesn't exist
  }

  // Open editor to create
  await editCredential(path);
  await notify(`Created credential: ${path}`, "passmenu");
}

// =============================================================================
// Temporary Email Management (mail.tm API)
// =============================================================================

async function fetchHydraCollection(
  url: string,
  options?: RequestInit
): Promise<unknown[]> {
  logDebug(`Fetching Hydra collection from ${url}`);
  const res = await fetch(url, options);
  if (!res.ok) {
    const errorText = await res.text();
    throw new Error(`Failed to fetch ${url}: ${res.statusText} - ${errorText}`);
  }
  const data = (await res.json()) as {
    "hydra:member": unknown[];
    "hydra:totalItems": number;
  };
  logDebug(`Fetched ${data["hydra:totalItems"]} items from ${url}`);
  return data["hydra:member"];
}

async function createTempEmail(): Promise<{ email: string; tempPass: string }> {
  // Fetch available domains
  const domainsData = (await fetchHydraCollection(
    "https://api.mail.tm/domains"
  )) as Array<{ isActive: boolean; isPrivate: boolean; domain: string }>;

  const activeDomains = domainsData
    .filter((d) => d.isActive && !d.isPrivate)
    .map((d) => d.domain);

  if (activeDomains.length === 0) {
    throw new Error("No active public domains available");
  }

  const domain =
    activeDomains[Math.floor(Math.random() * activeDomains.length)];
  logInfo(`Selected domain: ${domain}`);

  const randomName = crypto.randomBytes(8).toString("hex");
  const email = `${randomName}@${domain}`;
  const tempPass = crypto.randomBytes(16).toString("hex");

  // Create account
  logInfo(`Creating account for ${email}`);
  const createRes = await fetch("https://api.mail.tm/accounts", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ address: email, password: tempPass }),
  });

  if (!createRes.ok) {
    const errorText = await createRes.text();
    throw new Error(
      `Failed to create email account: ${createRes.statusText} - ${errorText}`
    );
  }

  logInfo(`Account created successfully for ${email}`);
  return { email, tempPass };
}

async function getMailTmToken(
  email: string,
  password: string
): Promise<string> {
  logDebug(`Fetching token for ${email}`);
  const tokenRes = await fetch("https://api.mail.tm/token", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ address: email, password }),
  });

  if (!tokenRes.ok) {
    const errorText = await tokenRes.text();
    throw new Error(
      `Failed to get token: ${tokenRes.statusText} - ${errorText}`
    );
  }

  const tokenData = (await tokenRes.json()) as { token: string };
  logInfo(`Token fetched successfully for ${email}`);
  return tokenData.token;
}

async function fetchMessages(token: string): Promise<unknown[]> {
  return await fetchHydraCollection("https://api.mail.tm/messages?page=1", {
    headers: { Authorization: `Bearer ${token}` },
  });
}

async function fetchMessage(
  token: string,
  messageId: string
): Promise<unknown> {
  logDebug(`Fetching message ${messageId}`);
  const url = `https://api.mail.tm/messages/${messageId}`;
  const msgRes = await fetch(url, {
    headers: { Authorization: `Bearer ${token}` },
  });

  if (!msgRes.ok) {
    const errorText = await msgRes.text();
    throw new Error(
      `Failed to fetch message: ${msgRes.statusText} - ${errorText}`
    );
  }

  const msg = await msgRes.json();
  logInfo(`Message ${messageId} fetched successfully`);
  return msg;
}

function parseField(content: string, field: string): string {
  for (const line of content.split("\n")) {
    if (line.startsWith(`${field}: `)) {
      return line.slice(`${field}: `.length).trim();
    }
  }
  return "";
}

async function handleViewMessages(
  menuCommand: string[],
  email: string,
  path: string,
  options: Options
): Promise<void> {
  const content = await $`pass show ${path}`.text();
  const password = parseField(content, "password");
  if (!password) {
    await notify("No password found", "passmenu");
    return;
  }

  try {
    const token = await getMailTmToken(email, password);
    logInfo(`Fetching messages for ${email}`);
    const messages = (await fetchMessages(token)) as Array<{
      id: string;
      from: { address: string };
      subject: string;
      text?: string;
      html?: string;
      createdAt: string;
    }>;

    if (messages.length === 0) {
      await notify(`No messages for ${email}`, "passmenu");
      return;
    }

    // Select message
    const msgOptions = messages.map(
      (m) => `${m.from.address}: ${m.subject.slice(0, 50)}`
    );
    const selectedMsgStr = await selectOption(
      menuCommand,
      msgOptions,
      "Select message:"
    );
    const selectedIndex = msgOptions.indexOf(selectedMsgStr);
    if (selectedIndex === -1) {
      await notify("No message selected", "passmenu");
      return;
    }

    // Fetch full message
    const msg = (await fetchMessage(token, messages[selectedIndex]!.id)) as {
      from: { address: string };
      subject: string;
      text?: string;
      html?: string;
      createdAt: string;
    };
    const body = msg.text || msg.html?.replace(/<[^>]*>/g, "") || "No body.";

    // Extract links from body
    const links: string[] = body.match(/https?:\/\/[^\s]+/g) || [];

    // Extract verification codes from both subject and body
    // Supports: 4-8 digit codes and "nnn nnn" spaced format (e.g., "123 456")
    const extractCodes = (text: string): string[] => {
      const codes = new Set<string>();

      // Standard 4-8 digit codes (use matchAll for proper capture group extraction)
      for (const match of text.matchAll(/(?:^|[<>\s])(\d{4,8})(?:$|[<>\s])/g)) {
        if (match[1]) codes.add(match[1]);
      }

      // "nnn nnn" format (6 digits with space separator, common in 2FA)
      for (const match of text.matchAll(/\b(\d{3})\s+(\d{3})\b/g)) {
        if (match[1] && match[2]) codes.add(`${match[1]}${match[2]}`);
      }

      return [...codes];
    };

    // Combine codes from subject line and body, deduplicated
    const codes = extractCodes(`${msg.subject} ${body}`);

    // Build options
    const messageOptions: string[] = ["Copy Full Message", "Open in Browser"];

    for (const link of links) {
      messageOptions.push(`Copy Link: ${link}`);
      if (options.autotype) {
        messageOptions.push(`Autotype Link: ${link}`);
      }
    }

    for (const code of codes) {
      messageOptions.push(`Copy Code: ${code.trim()}`);
      if (options.autotype) {
        messageOptions.push(`Autotype Code: ${code.trim()}`);
      }
    }

    const messageAction = await selectOption(
      menuCommand,
      messageOptions,
      "Choose action:"
    );
    if (!messageAction) {
      await notify("No action selected", "passmenu");
      return;
    }

    const copyCmd = await getCopyCommand();
    const typeCmd = await getTypeCommand();

    if (messageAction === "Copy Full Message") {
      const fullMessage = `From: ${msg.from.address}\nSubject: ${
        msg.subject
      }\nDate: ${new Date(msg.createdAt).toLocaleString()}\nBody:\n${body}`;
      await performAction(fullMessage, "copy", copyCmd);
      await notify("Message copied to clipboard", "passmenu");
    } else if (messageAction === "Open in Browser") {
      const tmpFile = `/tmp/passmenu-email-${messages[selectedIndex]!.id}.html`;
      const htmlContent = msg.html || `<pre>${msg.text}</pre>` || "No content";
      await Bun.write(tmpFile, htmlContent);
      await $`xdg-open ${tmpFile}`.nothrow();
      await notify("Opened in browser", "passmenu");
    } else if (messageAction.startsWith("Copy Link: ")) {
      const link = messageAction.slice("Copy Link: ".length);
      await performAction(link, "copy", copyCmd);
      await notify("Link copied to clipboard", "passmenu");
    } else if (messageAction.startsWith("Autotype Link: ")) {
      const link = messageAction.slice("Autotype Link: ".length);
      await performAction(link, "type", typeCmd);
      await notify("Link autotyped", "passmenu");
    } else if (messageAction.startsWith("Copy Code: ")) {
      const code = messageAction.slice("Copy Code: ".length);
      await performAction(code, "copy", copyCmd);
      await notify("Code copied to clipboard", "passmenu");
    } else if (messageAction.startsWith("Autotype Code: ")) {
      const code = messageAction.slice("Autotype Code: ".length);
      await performAction(code, "type", typeCmd);
      await notify("Code autotyped", "passmenu");
    }
  } catch (error) {
    logError("Failed to view messages", error);
    await notify("Failed to view messages", "passmenu");
  }
}

async function manageTempEmails(
  menuCommand: string[],
  passDir: string,
  options: Options
): Promise<void> {
  // List temp emails
  const tempListOutput =
    await $`find ${passDir} -type f -name '*.gpg' -path '*/temp_emails/*' -printf '%P\n' | sort`.text();
  const tempEntries = tempListOutput
    .trim()
    .split("\n")
    .filter(Boolean)
    .map((p) => p.replace(/\.gpg$/, ""));

  const tempEmails: TempEmail[] = tempEntries.map((path) => {
    const parts = path.split("/");
    const email = parts.pop()!;
    const associated = parts.slice(1).join("/"); // skip 'temp_emails'
    return { path, email, associated, display: `${email} - ${associated}` };
  });

  if (tempEmails.length === 0) {
    await notify("No temporary emails found", "passmenu");
    return;
  }

  // Select email
  const displayOptions = tempEmails.map((te) => te.display);
  const selectedDisplay = await selectOption(
    menuCommand,
    displayOptions,
    "Select email:"
  );
  if (!selectedDisplay) {
    await notify("No email selected", "passmenu");
    return;
  }

  const selected = tempEmails.find((te) => te.display === selectedDisplay)!;

  // Choose action
  const actions = [
    `📧 ${selected.email}`,
    "Copy Email",
    "Copy Password",
    "View Messages",
    "Delete Email",
  ];
  const action = await selectOption(
    menuCommand,
    actions,
    `Manage: ${selected.email}`
  );
  if (!action || action === `📧 ${selected.email}`) {
    if (!action) await notify("No action selected", "passmenu");
    return;
  }

  try {
    const copyCmd = await getCopyCommand();

    switch (action) {
      case "Copy Email":
        await performAction(selected.email, "copy", copyCmd);
        await notify("Email copied to clipboard", "passmenu");
        break;

      case "Copy Password": {
        const content = await $`pass show ${selected.path}`.text();
        const password = parseField(content, "password");
        if (!password) {
          await notify("No password found", "passmenu");
          return;
        }
        await performAction(password, "copy", copyCmd);
        await notify("Password copied to clipboard", "passmenu");
        break;
      }

      case "View Messages":
        await handleViewMessages(
          menuCommand,
          selected.email,
          selected.path,
          options
        );
        break;

      case "Delete Email":
        const confirm = await selectOption(
          menuCommand,
          ["No, keep it", "Yes, delete permanently"],
          `Delete ${selected.email}?`
        );

        if (confirm === "Yes, delete permanently") {
          await $`pass rm -f ${selected.path}`;
          await notify("Temp email deleted", "passmenu");
        }
        break;
    }
  } catch (error) {
    logError("Failed to perform action", error);
    await notify("Failed to perform action", "passmenu");
  }
}

// =============================================================================
// Generate Credential Flow
// =============================================================================

async function generateCredential(
  menuCommand: string[],
  passDir: string,
  action: "copy" | "type",
  actionCmd: string[]
): Promise<void> {
  const fields = [
    "email",
    "password",
    "password (small)",
    "username",
    "username (from name)",
    "full name",
    "phone number",
    "US address",
    "lorem ipsum",
  ];

  const selectedField = await selectOption(
    menuCommand,
    fields,
    "Select credential to generate"
  );
  if (!selectedField) {
    await notify("No field selected", "passmenu");
    return;
  }

  let value: string;
  let isTempEmail = false;

  if (selectedField === "email") {
    const emailType = await selectOption(
      menuCommand,
      ["Temporary (real)", "Fake (generated)"],
      "Email type"
    );
    if (!emailType) {
      await notify("No email type selected", "passmenu");
      return;
    }

    if (emailType === "Temporary (real)") {
      const path = (
        await $`echo -n | ${menuCommand} -p 'Enter associated path for temp email'`.text()
      ).trim();
      if (!path) {
        await notify("No path entered", "passmenu");
        return;
      }

      try {
        const { email, tempPass } = await createTempEmail();
        value = email;

        // Store temp creds
        const tempPath = `temp_emails/${path}/${email}`;
        const tempContent = `password: ${tempPass}\nassociated: ${path}\n`;
        await $`echo ${tempContent} | pass insert --multiline --force ${tempPath}`;
        logInfo(`Stored temp email creds for ${email} under ${tempPath}`);
        isTempEmail = true;
      } catch (error) {
        logError("Failed to generate temp email", error);
        await notify("Failed to create temp email", "passmenu");
        return;
      }
    } else {
      value = generateFakeEmail();
    }
  } else if (selectedField === "username (from name)") {
    // Special case: prompt for full name and derive username from it
    const fullName = (
      await $`echo -n | ${menuCommand} -p 'Enter full name:'`.text()
    ).trim();
    if (!fullName) {
      await notify("No name entered", "passmenu");
      return;
    }
    value = generateUsernameFromName(fullName);
  } else {
    const generator = credentialGenerators[selectedField];
    if (!generator) {
      await notify("No generator for selected field", "passmenu");
      return;
    }
    value = generator();
  }

  // Perform action immediately
  await performAction(value, action, actionCmd);
  await notify(
    action === "copy" ? "Copied to clipboard" : "Typed value",
    "passmenu"
  );

  // Prompt to save (unless temp email, already saved)
  if (!isTempEmail) {
    const path = (
      await $`echo -n | ${menuCommand} -p 'Enter path to save credential (empty to skip)'`.text()
    ).trim();
    if (path) {
      await appendToPass(path, selectedField, value);
      logInfo(`Appended ${selectedField} to ${path}`);
    }
  }
}

// =============================================================================
// Argument Parsing
// =============================================================================

function parseArgs(args: string[]): Options {
  const options: Options = {
    autotype: false,
    squash: false,
    fileisuser: false,
  };

  let i = 0;
  while (i < args.length) {
    const arg = args[i];
    switch (arg) {
      case "-a":
      case "--autotype":
        options.autotype = true;
        break;
      case "-s":
      case "--squash":
        options.squash = true;
        break;
      case "-f":
      case "--fileisuser":
        options.fileisuser = true;
        break;
      case "-c":
      case "--copy":
        i++;
        if (args[i] && !args[i]!.startsWith("-")) {
          options.copyCmd = args[i]!.split(" ");
        }
        break;
      case "-t":
      case "--type":
        i++;
        if (args[i] && !args[i]!.startsWith("-")) {
          options.typeCmd = args[i]!.split(" ");
        }
        break;
      case "-h":
      case "--help":
        console.log(`
Usage: passmenu [options]

Options:
  -a, --autotype    Enable autotype (username <tab> password)
  -c, --copy [cmd]  Copy to clipboard (optional custom command)
  -f, --fileisuser  Use file name as username (legacy, now default behavior)
  -s, --squash      Skip field select if only password exists
  -t, --type [cmd]  Type the selection (optional custom command)
  -h, --help        Show this help message
`);
        process.exit(0);
        break;
      default:
        console.error(`Unknown option: ${arg}`);
        process.exit(1);
    }
    i++;
  }

  return options;
}

// =============================================================================
// Main Entry Point
// =============================================================================

async function main(): Promise<void> {
  const options = parseArgs(Bun.argv.slice(2));

  // Determine action mode
  const action: "copy" | "type" =
    options.typeCmd || options.autotype ? "type" : "copy";
  const actionCmd =
    options.typeCmd ||
    options.copyCmd ||
    (action === "type" ? await getTypeCommand() : await getCopyCommand());

  const passDir =
    process.env.PASSWORD_STORE_DIR || `${process.env.HOME}/.password-store`;
  const menuCommand = await getMenuCommand();

  // Load persisted state
  const state = await loadState();
  const stateIsRecent = isStateRecent(state);

  let selected = "";
  let autoJumped = false;

  // Auto-jump to last entry if state is recent
  if (stateIsRecent && state.lastEntry) {
    selected = state.lastEntry;
    autoJumped = true;
  }

  // Main loop
  while (true) {
    if (!selected) {
      // List all entries
      const entries = await listPassEntries(passDir);
      const displayEntries = [...SPECIAL_ENTRIES, ...entries];

      // Default selection: 4th entry (index 3) = first real credential
      // (after Generate Credential, Manage Temp Emails, Create Credential)
      const defaultIndex = displayEntries.length > 3 ? 3 : 0;

      selected = await selectOption(
        menuCommand,
        displayEntries,
        "Select",
        stateIsRecent && state.lastEntry
          ? displayEntries.indexOf(state.lastEntry)
          : defaultIndex
      );

      if (!selected) {
        // User pressed Escape - clear state
        await clearState();
        process.exit(0);
      }
      autoJumped = false;
    }

    // Handle special entries
    if (selected === "Generate Credential") {
      await generateCredential(menuCommand, passDir, action, actionCmd);
      process.exit(0);
    }

    if (selected === "Manage Temp Emails") {
      await manageTempEmails(menuCommand, passDir, options);
      process.exit(0);
    }

    if (selected === "Create Credential") {
      await createCredential(menuCommand, passDir);
      process.exit(0);
    }

    // Fetch credential content
    let content = "";
    try {
      if (!selected) throw new Error("Empty selection");

      // Clean the selection: remove icons (e.g., "📁 ") and trim
      // This regex removes leading non-alphanumeric chars followed by space, or just trims
      // Specifically target the folder icon and space we add
      const cleanPath = selected
        .replace(/^[\p{Emoji}\u2000-\u3300]\s+/u, "")
        .trim();
      logDebug(`Fetching content for: ${cleanPath} (raw: ${selected})`);

      content = await $`pass show ${cleanPath}`.quiet().text();
    } catch (err) {
      logError(`Failed to read entry: ${selected}`, err);
      // Entry might have been deleted
      if (autoJumped) {
        selected = "";
        autoJumped = false;
        continue;
      }
      await notify(`Failed to read entry: ${selected}`, "passmenu");
      process.exit(1);
    }

    // Parse credential
    const credential = parseCredential(content, selected);
    const fieldOptions = buildFieldOptions(
      credential,
      selected,
      options.autotype
    );

    // Determine initial selection for field menu
    // 2nd entry (index 1) is the first real field (after credential path)
    let initialFieldIndex = 1;
    if (stateIsRecent && selected === state.lastEntry && state.lastField) {
      const savedIdx = fieldOptions.indexOf(state.lastField);
      if (savedIdx !== -1) {
        initialFieldIndex = savedIdx;
      }
    }

    // Squash: skip field selection if only password exists
    let selectedField = "";
    if (
      options.squash &&
      fieldOptions.length === 2 &&
      !options.autotype // Only path + password
    ) {
      selectedField = "password";
    } else {
      selectedField = await selectOption(
        menuCommand,
        fieldOptions,
        selected,
        initialFieldIndex
      );
    }

    if (!selectedField) {
      // User pressed Escape
      if (autoJumped) {
        // Go back to main menu
        selected = "";
        autoJumped = false;
        await clearState();
        continue;
      }
      await clearState();
      process.exit(0);
    }

    // Handle credential path selection (edit options)
    if (selectedField.startsWith("📁 ")) {
      const result = await showEditOptions(menuCommand, selected, passDir);
      if (result === "exit") {
        process.exit(0);
      }
      if (result === "deleted" || result === "moved") {
        selected = "";
        await clearState();
        continue;
      }
      continue;
    }

    // Handle field actions
    let value = "";

    if (selectedField === "password") {
      value = credential.password;
    } else if (selectedField === "otp") {
      value = (await $`pass otp ${selected}`.text()).trim();
    } else if (selectedField === "autotype") {
      // Autotype: username <tab> password
      const username =
        credential.fields["username"] ||
        credential.fields["login"] ||
        credential.fields["user"] ||
        credential.fields["username (from path)"] ||
        "";
      const copyCmd = await getCopyCommand();

      // Always copy password to clipboard as backup
      await performAction(credential.password, "copy", copyCmd);

      if (action === "type") {
        if (username) {
          await performAction(username, "type", actionCmd);
          const tabCmd = await getTabCommand();
          await $`${tabCmd}`;
        }
        await performAction(credential.password, "type", actionCmd);
        await notify(
          "Autotyped credentials (password also copied)",
          "passmenu"
        );
      } else {
        await notify("Password copied to clipboard", "passmenu");
      }

      await saveState({ lastEntry: selected, lastField: selectedField });
      process.exit(0);
    } else {
      // Regular field
      value = credential.fields[selectedField] || "";
    }

    if (!value) {
      await notify(`No value for ${selectedField}`, "passmenu");
      continue;
    }

    // Perform the action
    await performAction(value, action, actionCmd);
    await notify(
      action === "copy" ? "Copied to clipboard" : "Typed value",
      "passmenu"
    );

    // Save state and exit
    await saveState({ lastEntry: selected, lastField: selectedField });
    process.exit(0);
  }
}

// =============================================================================
// Entry Point
// =============================================================================

main().catch(async (error) => {
  logError("Unhandled error", error);
  await notify("An error occurred", "passmenu");
  process.exit(1);
});
