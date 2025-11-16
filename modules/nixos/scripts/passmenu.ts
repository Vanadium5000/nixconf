#!/usr/bin/env bun
// passmenu.ts - Bun.js TypeScript script for browsing and selecting passwords from password-store using rofi or wofi
import { $ } from "bun";
import { faker } from "@faker-js/faker";
import crypto from "node:crypto";

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
  copyCmd: string[] | undefined;
  typeCmd: string[] | undefined;
}

// Function to generate fake signup data
function generateFakeData() {
  const username = faker.internet.username();
  const fullName = faker.person.fullName();
  const password = crypto.randomBytes(32).toString("base64");
  return { username, fullName, password };
}

// Function to create a temporary email using mail.tm API
async function createTempEmail(): Promise<{ email: string; tempPass: string }> {
  const domainsRes = await fetch("https://api.mail.tm/domains");
  if (!domainsRes.ok) throw new Error("Failed to fetch domains");
  const domainsData = (await domainsRes.json()) as any;
  const domains = domainsData.data.map((d: any) => d.domain);
  if (domains.length === 0) throw new Error("No domains available");
  const domain = domains[Math.floor(Math.random() * domains.length)];
  const randomName = crypto.randomBytes(8).toString("hex");
  const email = `${randomName}@${domain}`;
  const tempPass = crypto.randomBytes(16).toString("hex");
  const createRes = await fetch("https://api.mail.tm/accounts", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ address: email, password: tempPass }),
  });
  if (!createRes.ok) throw new Error("Failed to create email account");
  return { email, tempPass };
}

// Function to fetch mail.tm token
async function getMailTmToken(
  email: string,
  password: string
): Promise<string> {
  const tokenRes = await fetch("https://api.mail.tm/token", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ address: email, password }),
  });
  if (!tokenRes.ok) throw new Error("Failed to get token");
  const tokenData = (await tokenRes.json()) as any;
  return tokenData.token;
}

// Function to fetch messages for an email
async function fetchMessages(token: string): Promise<any[]> {
  const messagesRes = await fetch(
    "https://api.mail.tm/messages?page=1&limit=50",
    {
      headers: { Authorization: `Bearer ${token}` },
    }
  );
  if (!messagesRes.ok) throw new Error("Failed to fetch messages");
  const messagesData = (await messagesRes.json()) as any;
  return messagesData.data;
}

// Function to fetch a single message
async function fetchMessage(token: string, messageId: string): Promise<any> {
  const msgRes = await fetch(`https://api.mail.tm/messages/${messageId}`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!msgRes.ok) throw new Error("Failed to fetch message");
  return await msgRes.json();
}

// Function to handle generating fake account
async function generateFakeAccount(
  menuCommand: string[],
  passDir: string,
  action: string,
  actionCmd: string[]
) {
  try {
    // Prompt for path
    const pathPrompt = (
      await $`echo -n | ${menuCommand} -p 'Enter path for new entry (e.g., personal/site/account):'`.text()
    ).trim();
    if (!pathPrompt) {
      logInfo("User cancelled path entry");
      return;
    }

    // Generate fake data
    const { username, fullName, password } = generateFakeData();
    let content = `${password}\nusername: ${username}\nname: ${fullName}\n`;

    // Prompt for temp email
    let email = "";
    let tempPass = "";
    const genEmailPrompt = (
      await $`printf 'Yes\nNo\n' | ${menuCommand} -p 'Generate temporary email? '`.text()
    ).trim();
    if (genEmailPrompt === "Yes") {
      try {
        const tempEmailData = await createTempEmail();
        email = tempEmailData.email;
        tempPass = tempEmailData.tempPass;
        content += `email: ${email}\n`;
        // Store temp email credentials with association
        const tempContent = `password: ${tempPass}\nassociated: ${pathPrompt}\n`;
        await $`echo -n ${tempContent} | pass insert --multiline --force emails/temp/${email}`;
        logInfo(`Stored temp email credentials for ${email}`);
      } catch (error) {
        logError("Failed to generate and store temp email", error);
        console.error("Failed to generate temp email. Continuing without it.");
      }
    }

    // Preview generated data
    console.log("Generated data:");
    console.log(content);

    // Confirm storage
    const confirmPrompt = (
      await $`printf 'Yes\nNo\n' | ${menuCommand} -p 'Store this in password-store? '`.text()
    ).trim();
    if (confirmPrompt === "Yes") {
      await $`echo -n ${content} | pass insert --multiline --force ${pathPrompt}`;
      logInfo(`Stored new entry at ${pathPrompt}`);
      if (email) {
        logInfo(`Associated temp email: ${email}`);
      }
      // Optionally perform action on password (e.g., copy)
      if (action === "copy") {
        await $`echo -n ${password} | xargs ${actionCmd}`;
        logInfo("Copied generated password to clipboard");
      }
    } else {
      logInfo("Cancelled storing new entry");
    }
  } catch (error) {
    logError("Error in generateFakeAccount", error);
    console.error("Failed to generate fake account:", error);
  }
}

// Function to handle managing temp emails
async function manageTempEmails(menuCommand: string[], entries: string[]) {
  try {
    const tempPrefix = "emails/temp/";
    const tempEmails = entries
      .filter((e) => e.startsWith(tempPrefix))
      .map((e) => e.slice(tempPrefix.length));

    if (tempEmails.length === 0) {
      console.log("No temporary emails found in password-store.");
      return;
    }

    // Select email
    const selectEmailPrompt = (
      await $`printf '%s\n' ${tempEmails} | ${menuCommand} -p 'Select email to view:'`.text()
    ).trim();
    if (!selectEmailPrompt) {
      logInfo("User cancelled email selection");
      return;
    }
    const selectedEmail = selectEmailPrompt;

    // Get credentials
    const credsContent =
      await $`pass show ${tempPrefix}${selectedEmail}`.text();
    const credsLines = credsContent.trim().split("\n");
    const passwordLine = credsLines.find((l) => l.startsWith("password:"));
    const credsPassword = passwordLine
      ? (passwordLine.split(":")[1] as string).trim()
      : "";
    if (!credsPassword) {
      throw new Error("No password found for selected email");
    }

    // Get token
    const token = await getMailTmToken(selectedEmail, credsPassword);

    // Fetch messages
    const messages = await fetchMessages(token);
    if (messages.length === 0) {
      console.log(`No messages found for ${selectedEmail}.`);
      return;
    }

    // Select message
    const messageOptions = messages.map(
      (m: any) => `${m.from.address}: ${m.subject.slice(0, 50)}`
    );
    const selectMsgPrompt = (
      await $`printf '%s\n' ${messageOptions} | ${menuCommand} -p 'Select message:'`.text()
    ).trim();
    if (!selectMsgPrompt) {
      logInfo("User cancelled message selection");
      return;
    }
    const selectedIndex = messageOptions.indexOf(selectMsgPrompt);
    if (selectedIndex === -1) {
      throw new Error("Invalid message selection");
    }
    const selectedMsg = messages[selectedIndex];

    // Fetch and display message
    const msg = await fetchMessage(token, selectedMsg.id);
    console.log("Message Details:");
    console.log(`From: ${msg.from.address}`);
    console.log(`Subject: ${msg.subject}`);
    console.log(`Date: ${new Date(msg.createdAt).toLocaleString()}`);
    console.log("Body:");
    if (msg.text) {
      console.log(msg.text);
    } else if (msg.html) {
      console.log("HTML body (displaying as plain text):");
      console.log(msg.html.replace(/<[^>]*>/g, "")); // Basic strip for display
    } else {
      console.log("No body content available.");
    }
  } catch (error) {
    logError("Error in manageTempEmails", error);
    console.error("Failed to manage temp emails:", error);
  }
}

async function main() {
  let args = Bun.argv.slice(2);
  let options: Options = {
    autotype: false,
    squash: false,
    fileisuser: false,
    copyCmd: undefined,
    typeCmd: undefined,
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
  -a, --autotype Enable autotype option (username <tab> password)
  -c, --copy [cmd] Copy to clipboard (default: ${defaultCopyCommand})
  -f, --fileisuser Use password file name as username if not specified
  -s, --squash Skip field selection if only password is present
  -t, --type [cmd] Type the selection (default: ${defaultTypeCommand})
  -h, --help Show this help message
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
  if ((options.typeCmd && options.typeCmd.length > 0) || options.autotype) {
    action = "type";
    actionCmd =
      options.typeCmd && options.typeCmd.length > 0
        ? options.typeCmd
        : await getTypeCommand();
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
      await $`find ${passDir} -type f -name '*.gpg' -printf '%P\n' | sed 's/\\.gpg$//' | sort`.text();
    logDebug(`Found password entries: ${listOutput.trim().split("\n").length}`);
  } catch (error) {
    logError("Failed to list password entries", error);
    console.error("Failed to list password entries:", error);
    process.exit(1);
  }

  const entrySuffix = ".gpg";
  const entries = listOutput
    .trim()
    .split("\n")
    .filter(Boolean)
    .map((item) =>
      item.endsWith(entrySuffix) ? item.slice(0, -entrySuffix.length) : item
    );

  if (entries.length === 0) {
    logError("No password entries found in password store");
    console.error("No password entries found in password store.");
  }
  logInfo(`Found ${entries.length} password entries`);

  // Add special entries for new functionalities
  const specialEntries = [
    "New: Generate fake account",
    "Emails: Manage temp emails",
  ];
  const displayEntries = [...specialEntries, ...entries];

  // Get menu command
  const menuCommand = await getMenuCommand();
  logDebug(`Menu command: ${menuCommand.join(" ")}`);

  // Show menu to select entry
  let selectEntryPrompt: string;
  try {
    logDebug("Showing password selection menu");
    selectEntryPrompt =
      await $`printf '%s\n' ${displayEntries} | ${menuCommand} -p 'Select password:'`.text();
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
  logInfo(`Selected: ${selected}`);

  // Handle special entries
  if (specialEntries.includes(selected)) {
    if (selected === "New: Generate fake account") {
      await generateFakeAccount(menuCommand, passDir, action, actionCmd);
    } else if (selected === "Emails: Manage temp emails") {
      await manageTempEmails(menuCommand, entries);
    }
    process.exit(0);
  }

  // Proceed with regular password handling
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
        // Also copy to clipboard when autotyping
        const copyCmd = await getCopyCommand();
        logDebug("Copying password to clipboard during autotype");
        await $`echo -n ${password} | xargs ${copyCmd}`;
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
