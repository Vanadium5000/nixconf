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
// Notification utility
async function notify(message: string, title: string = "passmenu") {
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
// Get copy command
async function getCopyCommand(): Promise<string[]> {
  if (!!process.env.WAYLAND_DISPLAY && (await commandExists("wl-copy"))) {
    return ["wl-copy"];
  } else if (await commandExists("xclip")) {
    return ["xclip", "-selection", "clipboard"];
  } else {
    throw new Error("Neither wl-copy nor xclip found.");
  }
}
// Get type command
async function getTypeCommand(): Promise<string[]> {
  if (!!process.env.WAYLAND_DISPLAY && (await commandExists("wtype"))) {
    return ["wtype"];
  } else if (await commandExists("xdotool")) {
    return ["xdotool", "type", "--clearmodifiers"];
  } else if (await commandExists("ydotool")) {
    return ["ydotool", "type", "--"];
  } else {
    throw new Error("Neither wtype, xdotool, nor ydotool found.");
  }
}
// Get tab command
async function getTabCommand(): Promise<string[]> {
  if (!!process.env.WAYLAND_DISPLAY && (await commandExists("wtype"))) {
    return ["wtype", "-k", "tab"];
  } else if (await commandExists("xdotool")) {
    return ["xdotool", "key", "Tab"];
  } else if (await commandExists("ydotool")) {
    return ["ydotool", "key", "15:1", "15:0"];
  } else {
    throw new Error("No tool found for tab key.");
  }
}
// Helper to perform copy or type action
async function performAction(
  value: string,
  action: "copy" | "type",
  actionCmd: string[]
) {
  const proc = Bun.spawn(actionCmd, {
    stdin: "pipe",
  });
  proc.stdin.write(value);
  proc.stdin.end();
  await proc.exited;
}
// Helper to select from menu
async function selectOption(
  menuCommand: string[],
  options: string[],
  prompt: string
): Promise<string> {
  if (options.length === 0) return "";
  const selected = (
    await $`printf '%s\n' ${options} | ${menuCommand} -p ${prompt}`.text()
  ).trim();
  return selected;
}
// Helper to parse password from pass content
function parsePassword(content: string): string {
  return content.split("\n")[0]?.trim() || "";
}
// Helper to parse field from pass content
function parseField(content: string, field: string): string {
  const lines = content.split("\n");
  for (const line of lines) {
    if (line.startsWith(`${field}: `)) {
      return line.slice(`${field}: `.length).trim();
    }
  }
  return "";
}
interface Options {
  autotype: boolean;
  squash: boolean;
  fileisuser: boolean;
  copyCmd: string[] | undefined;
  typeCmd: string[] | undefined;
}
// Credential generators
const credentialGenerators: Record<string, () => string> = {
  password: () => crypto.randomBytes(15).toString("base64"), // 20 characters
  username: () => faker.internet.username(),
  "full name": () => faker.person.fullName(),
  "phone number": () => faker.phone.number({ style: "international" }),
  "lorem ipsum": () => faker.lorem.paragraph(),
  // Add more as needed
};
// Generate fake email (non-temporary)
function generateFakeEmail(): string {
  return faker.internet.email();
}
// Helper to fetch and parse Hydra collections from mail.tm API
async function fetchHydraCollection(
  url: string,
  options?: RequestInit
): Promise<any[]> {
  logDebug(`Fetching Hydra collection from ${url}`);
  const res = await fetch(url, options);
  if (!res.ok) {
    const errorText = await res.text();
    throw new Error(`Failed to fetch ${url}: ${res.statusText} - ${errorText}`);
  }
  const data = (await res.json()) as any;
  logDebug(`Fetched ${data["hydra:totalItems"]} items from ${url}`);
  return data["hydra:member"];
}
// Create temporary email using mail.tm API with error handling
async function createTempEmail(): Promise<{ email: string; tempPass: string }> {
  try {
    // Fetch available domains
    const domainsData = await fetchHydraCollection(
      "https://api.mail.tm/domains"
    );
    const activeDomains = domainsData
      .filter((d: any) => d.isActive && !d.isPrivate)
      .map((d: any) => d.domain);
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
  } catch (error) {
    logError("Temp email creation failed", error);
    throw error;
  }
}
// Fetch mail.tm token
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
// Fetch messages (first page)
async function fetchMessages(token: string): Promise<any[]> {
  const url = "https://api.mail.tm/messages?page=1";
  return await fetchHydraCollection(url, {
    headers: { Authorization: `Bearer ${token}` },
  });
}
// Fetch single message
async function fetchMessage(token: string, messageId: string): Promise<any> {
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
// Append field to pass entry (create if not exists)
async function appendToPass(
  path: string,
  field: string,
  value: string
): Promise<void> {
  let existing = await $`pass show ${path}`.text().catch(() => "");
  let lines = existing.trim().split("\n").filter(Boolean);
  if (field === "password") {
    // Set as first line if password
    if (lines.length === 0 || !(lines[0] as string).includes(":")) {
      lines.unshift(value);
    } else {
      lines.unshift(value);
    }
  } else {
    lines.push(`${field}: ${value}`);
  }
  const content = lines.join("\n") + "\n";
  await $`echo ${content} | pass insert --multiline --force ${path}`;
}
// Handle generating credential
async function generateCredential(
  menuCommand: string[],
  passDir: string,
  action: "copy" | "type",
  actionCmd: string[]
) {
  // Select field
  const fields = [
    "email",
    "password",
    "username",
    "full name",
    "phone number",
    "lorem ipsum",
  ];
  const selectedField = (
    await $`printf '%s\n' ${fields} | ${menuCommand} -p 'Select credential to generate'`.text()
  ).trim();
  if (!selectedField) {
    await notify("No field selected", "passmenu");
    return;
  }
  let value: string;
  let isTempEmail = false;
  if (selectedField === "email") {
    // Ask temp or fake
    const emailType = (
      await $`printf 'Temporary (real)\nFake (generated)\n' | ${menuCommand} -p 'Email type'`.text()
    ).trim();
    if (!emailType) {
      await notify("No email type selected", "passmenu");
      return;
    }
    if (emailType === "Temporary (real)") {
      // Prompt for path for temp email association
      const path = (
        await $`echo -n | ${menuCommand} -p 'Enter associated path for temp email (e.g., personal/site/account)'`.text()
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
        console.error("Failed to generate temp email.");
        return;
      }
    } else {
      value = generateFakeEmail();
    }
  } else {
    const generator = credentialGenerators[selectedField];
    if (!generator) {
      console.error("No generator for selected field.");
      return;
    }
    value = generator();
  }
  // Perform action (copy/type) before prompting for save path
  await performAction(value, action, actionCmd);
  if (action === "copy") {
    await notify("Copied to clipboard", "passmenu");
  } else {
    await notify("Typed value", "passmenu");
  }
  // If not temp email, prompt for path and save
  if (!isTempEmail) {
    const path = (
      await $`echo -n | ${menuCommand} -p 'Enter path to save credential (e.g., personal/site/account)'`.text()
    ).trim();
    if (!path) {
      await notify("No path entered", "passmenu");
      return;
    }
    await appendToPass(path, selectedField, value);
    logInfo(`Appended ${selectedField} to ${path}`);
  }
}
// Handle managing temp emails with new structure and enhanced options
async function manageTempEmails(
  menuCommand: string[],
  passDir: string,
  options: Options
) {
  // List temp emails from new structure
  const tempListOutput =
    await $`find ${passDir} -type f -name '*.gpg' -path '*/temp_emails/*' -printf '%P\n' | sort`.text();
  const tempEntries = tempListOutput
    .trim()
    .split("\n")
    .filter(Boolean)
    .map((p) => p.replace(/\.gpg$/, ""));

  const tempEmails = tempEntries.map((path) => {
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
    "Copy Email",
    "Copy Password",
    "View Messages",
    "Delete Email",
  ];
  const action = await selectOption(menuCommand, actions, "Choose action:");
  if (!action) {
    await notify("No action selected", "passmenu");
    return;
  }

  try {
    switch (action) {
      case "Copy Email":
        await performAction(selected.email, "copy", await getCopyCommand());
        await notify("Email copied to clipboard", "passmenu");
        break;

      case "Copy Password":
        const content = await $`pass show ${selected.path}`.text();
        const password = parseField(content, "password");
        if (!password) {
          await notify("No password found", "passmenu");
          return;
        }
        await performAction(password, "copy", await getCopyCommand());
        await notify("Password copied to clipboard", "passmenu");
        break;

      case "View Messages":
        await handleViewMessages(
          menuCommand,
          selected.email,
          selected.path,
          options
        );
        break;

      case "Delete Email":
        await $`pass rm ${selected.path}`;
        await notify("Temp email deleted", "passmenu");
        break;
    }
  } catch (error) {
    logError("Failed to perform action", error);
    console.error("Failed to perform action:", error);
  }
}

// Handle viewing messages for a temp email
async function handleViewMessages(
  menuCommand: string[],
  email: string,
  path: string,
  options: Options
) {
  const content = await $`pass show ${path}`.text();
  const password = parseField(content, "password");
  if (!password) {
    await notify("No password found", "passmenu");
    return;
  }

  try {
    const token = await getMailTmToken(email, password);
    logInfo(`Fetching messages for ${email}`);
    const messages = await fetchMessages(token);
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

    // Fetch message
    const msg = await fetchMessage(token, messages[selectedIndex].id);
    const body = msg.text || msg.html?.replace(/<[^>]*>/g, "") || "No body.";
    const links: string[] = body.match(/https?:\/\/[^\s]+/g) || [];
    const codes: string[] =
      body.match(/(?:^|[<>\s])(\d{4,8})(?:$|[<>\s])/g) || []; // 4-8 digit codes next to whitespace or angular brackets

    // Build options
    const linkOptions: string[] = [];
    for (const l of links) {
      linkOptions.push(`Copy Link: ${l}`);
      if (options.autotype) {
        linkOptions.push(`Autotype Link: ${l}`);
      }
    }
    const codeOptions: string[] = [];
    for (const c of codes) {
      codeOptions.push(`Copy Code: ${c}`);
      if (options.autotype) {
        codeOptions.push(`Autotype Code: ${c}`);
      }
    }
    const messageOptions = [
      "Copy Full Message",
      ...linkOptions,
      ...codeOptions,
    ];

    const messageAction = await selectOption(
      menuCommand,
      messageOptions,
      "Choose action for message:"
    );
    if (!messageAction) {
      await notify("No action selected", "passmenu");
      return;
    }

    if (messageAction === "Copy Full Message") {
      const fullMessage = `From: ${msg.from.address}\nSubject: ${
        msg.subject
      }\nDate: ${new Date(msg.createdAt).toLocaleString()}\nBody:\n${body}`;
      console.log(fullMessage); // Keep console for display
      await performAction(fullMessage, "copy", await getCopyCommand());
      await notify("Message copied to clipboard", "passmenu");
    } else if (messageAction.startsWith("Copy Link: ")) {
      const link = messageAction.slice("Copy Link: ".length);
      await performAction(link, "copy", await getCopyCommand());
      await notify("Link copied to clipboard", "passmenu");
    } else if (messageAction.startsWith("Autotype Link: ")) {
      const link = messageAction.slice("Autotype Link: ".length);
      await performAction(link, "type", await getTypeCommand());
      await notify("Link autotyped", "passmenu");
    }
  } catch (error) {
    logError("Failed to view messages", error);
    console.error("Failed to view messages:", error);
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
      options.copyCmd =
        args[i] && !(args[i] as string).startsWith("-")
          ? (args[i] as string).split(" ")
          : await getCopyCommand();
    } else if (arg === "-t" || arg === "--type") {
      i++;
      options.typeCmd =
        args[i] && !(args[i] as string).startsWith("-")
          ? (args[i] as string).split(" ")
          : await getTypeCommand();
    } else if (arg === "-h" || arg === "--help") {
      console.log(`
Usage: passmenu [options]
Options:
  -a, --autotype Enable autotype (username <tab> password)
  -c, --copy [cmd] Copy to clipboard
  -f, --fileisuser Use file name as username
  -s, --squash Skip field select if only password
  -t, --type [cmd] Type the selection
  -h, --help Show help
`);
      process.exit(0);
    } else {
      console.error(`Unknown option: ${arg}`);
      process.exit(1);
    }
    i++;
  }
  // Determine action
  let action: "copy" | "type" = "copy";
  let actionCmd = options.copyCmd || (await getCopyCommand());
  if (options.typeCmd || options.autotype) {
    action = "type";
    actionCmd = options.typeCmd || (await getTypeCommand());
  }
  const passDir =
    process.env.PASSWORD_STORE_DIR || `${process.env.HOME}/.password-store`;
  // List entries
  const suffix = ".gpg";
  const listOutput =
    await $`find ${passDir} -type f -name '*.gpg' -printf '%P\n' | sed 's/\\.gpg$//' | sort`.text();
  const entries = listOutput
    .trim()
    .split("\n")
    .filter(Boolean)
    .map((str) => {
      if (str.endsWith(suffix)) {
        return str.slice(0, -suffix.length);
      }
      return str; // Return unchanged if no match
    })
    .filter((e) => !e.startsWith("temp_emails/"));
  // Special entries
  const specialEntries = ["Generate Credential", "Manage Temp Emails"];
  const displayEntries = [...specialEntries, ...entries];
  // Menu
  const menuCommand = await getMenuCommand();
  const selected = (
    await $`printf '%s\n' ${displayEntries} | ${menuCommand} -p 'Select'`.text()
  ).trim();
  if (!selected) {
    await notify("No selection made", "passmenu");
    process.exit(0);
  }
  // Handle special
  if (selected === "Generate Credential") {
    await generateCredential(menuCommand, passDir, action, actionCmd);
    process.exit(0);
  } else if (selected === "Manage Temp Emails") {
    await manageTempEmails(menuCommand, passDir, options);
    process.exit(0);
  }
  // Regular pass handling
  const content = await $`pass show ${selected}`.text();
  const lines = content.trim().split("\n");
  let password = "";
  let fields: Record<string, string> = {};
  let hasOtpauth = false;

  if (lines[0] && lines[0].includes(":")) {
    // Parse all lines as key: value pairs
    for (const line of lines) {
      const trimmed = line.trim();
      if (trimmed.startsWith("otpauth://")) {
        hasOtpauth = true;
      } else if (trimmed.includes(":")) {
        const parts = trimmed.split(":");
        const key = parts.shift();
        if (key) {
          const k = key.trim().toLowerCase();
          const v = parts.join(":").trim();
          if (k === "password") {
            password = v;
          } else {
            fields[k] = v;
          }
        }
      }
    }
  } else {
    // Standard pass format: first line is password, rest are key: value
    password = lines[0]?.trim() || "";
    for (let j = 1; j < lines.length; j++) {
      const line = lines[j]?.trim() || "";
      if (line.startsWith("otpauth://")) {
        hasOtpauth = true;
      } else if (line.includes(":")) {
        const [key, ...val] = line.split(":");
        fields[(key as string).trim().toLowerCase()] = val.join(":").trim();
      }
    }
  }
  if (!fields["username"] && options.fileisuser) {
    fields["username"] = selected.split("/").pop() || "";
  }
  let fieldOptions = ["password", ...Object.keys(fields)];
  if (hasOtpauth) fieldOptions.push("otp");
  if (options.autotype) fieldOptions.push("autotype");
  fieldOptions = [...new Set(fieldOptions)];
  let selectedField = "";
  if (options.squash && fieldOptions.length === 1 && !options.autotype) {
    selectedField = "password";
  } else {
    selectedField = (
      await $`printf '%s\n' ${fieldOptions} | ${menuCommand} -p 'Select field'`.text()
    ).trim();
  }
  if (!selectedField) {
    await notify("No field selected", "passmenu");
    process.exit(0);
  }
  let value = "";
  if (selectedField === "password") {
    value = password;
  } else if (selectedField === "otp") {
    value = (await $`pass otp ${selected}`.text()).trim();
  } else if (selectedField === "autotype") {
    // Autotype
    const username = fields["username"] || "";
    const copyCmd = await getCopyCommand();
    await performAction(password, "copy", copyCmd); // Always copy password to clipboard
    if (action === "type") {
      if (username) {
        await performAction(username, "type", actionCmd);
        const tabCmd = await getTabCommand();
        await $`${tabCmd}`;
      }
      await performAction(password, "type", actionCmd);
      await notify(
        "Autotyped username and password (password copied to clipboard)",
        "passmenu"
      );
    } else {
      await notify("Password copied to clipboard", "passmenu");
    }
    process.exit(0);
  } else {
    value = fields[selectedField] || "";
  }
  // Perform action
  await performAction(value, action, actionCmd);
  if (action === "copy") {
    await notify("Copied to clipboard", "passmenu");
  } else {
    await notify("Typed value", "passmenu");
  }
  process.exit(0);
}
main().catch(async (error) => {
  console.error("Error:", error);
  await notify("An error occurred", "passmenu");
  process.exit(1);
});
