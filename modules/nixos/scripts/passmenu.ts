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
interface Options {
  autotype: boolean;
  squash: boolean;
  fileisuser: boolean;
  copyCmd: string[] | undefined;
  typeCmd: string[] | undefined;
}
// Credential generators
const credentialGenerators: Record<string, () => string> = {
  password: () => crypto.randomBytes(32).toString("base64"),
  username: () => faker.internet.username(),
  "full name": () => faker.person.fullName(),
  // Add more as needed
};
// Generate fake email (non-temporary)
function generateFakeEmail(): string {
  return faker.internet.email();
}
// Create temporary email using mail.tm API with error handling
async function createTempEmail(): Promise<{ email: string; tempPass: string }> {
  try {
    const domainsRes = await fetch("https://api.mail.tm/domains");
    if (!domainsRes.ok) {
      throw new Error(`Failed to fetch domains: ${domainsRes.statusText}`);
    }
    const domainsData = (await domainsRes.json()) as {
      data: { domain: string }[];
    };
    const domains = domainsData.data.map((d) => d.domain);
    if (domains.length === 0) {
      throw new Error("No domains available");
    }
    const domain = domains[Math.floor(Math.random() * domains.length)];
    const randomName = crypto.randomBytes(8).toString("hex");
    const email = `${randomName}@${domain}`;
    const tempPass = crypto.randomBytes(16).toString("hex");
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
  const tokenRes = await fetch("https://api.mail.tm/token", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ address: email, password }),
  });
  if (!tokenRes.ok) {
    throw new Error(`Failed to get token: ${tokenRes.statusText}`);
  }
  const tokenData = (await tokenRes.json()) as { token: string };
  return tokenData.token;
}
// Fetch messages
async function fetchMessages(token: string): Promise<any[]> {
  const messagesRes = await fetch(
    "https://api.mail.tm/messages?page=1&limit=50",
    {
      headers: { Authorization: `Bearer ${token}` },
    }
  );
  if (!messagesRes.ok) {
    throw new Error(`Failed to fetch messages: ${messagesRes.statusText}`);
  }
  const messagesData = (await messagesRes.json()) as { data: any[] };
  return messagesData.data;
}
// Fetch single message
async function fetchMessage(token: string, messageId: string): Promise<any> {
  const msgRes = await fetch(`https://api.mail.tm/messages/${messageId}`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!msgRes.ok) {
    throw new Error(`Failed to fetch message: ${msgRes.statusText}`);
  }
  return await msgRes.json();
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
  action: string,
  actionCmd: string[]
) {
  // Prompt for path
  const path = (
    await $`echo -n | ${menuCommand} -p 'Enter path for new entry (e.g., personal/site/account):'`.text()
  ).trim();
  if (!path) return;
  // Select field
  const fields = ["password", "username", "full name", "email"];
  const selectedField = (
    await $`printf '%s\n' ${fields} | ${menuCommand} -p 'Select credential to generate:'`.text()
  ).trim();
  if (!selectedField) return;
  let value: string;
  if (selectedField === "email") {
    // Ask temp or fake
    const emailType = (
      await $`printf 'Temporary (real)\nFake (generated)\n' | ${menuCommand} -p 'Email type:'`.text()
    ).trim();
    if (!emailType) return;
    if (emailType === "Temporary (real)") {
      try {
        const { email, tempPass } = await createTempEmail();
        value = email;
        // Store temp creds
        const tempContent = `password: ${tempPass}\nassociated: ${path}\n`;
        await $`echo ${tempContent} | pass insert --multiline --force emails/temp/${email}`;
        logInfo(`Stored temp email creds for ${email}`);
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
  // Preview and confirm
  console.log(`Generated ${selectedField}: ${value}`);
  const confirm = (
    await $`printf 'Yes\nNo\n' | ${menuCommand} -p 'Store and perform action?'`.text()
  ).trim();
  if (confirm !== "Yes") return;
  // Append to path
  await appendToPass(path, selectedField, value);
  logInfo(`Appended ${selectedField} to ${path}`);
  // Perform action (copy/type)
  if (action === "copy") {
    await $`echo -n ${value} | ${actionCmd}`;
    logInfo("Copied to clipboard");
  } else {
    await $`echo -n ${value} | ${actionCmd}`;
    logInfo("Typed value");
  }
}
// Handle managing temp emails (browse addresses, view messages)
async function manageTempEmails(menuCommand: string[], entries: string[]) {
  const tempPrefix = "emails/temp/";
  const tempEmails = entries
    .filter((e) => e.startsWith(tempPrefix))
    .map((e) => e.slice(tempPrefix.length));
  if (tempEmails.length === 0) {
    console.log("No temp emails found.");
    return;
  }
  // Select email
  const selectedEmail = (
    await $`printf '%s\n' ${tempEmails} | ${menuCommand} -p 'Select email:'`.text()
  ).trim();
  if (!selectedEmail) return;
  // Get creds
  const creds = await $`pass show ${tempPrefix}${selectedEmail}`.text();
  const password = creds
    .split("\n")
    .find((l) => l.startsWith("password:"))
    ?.split(":")[1]
    ?.trim();
  if (!password) {
    console.error("No password for email.");
    return;
  }
  // Get token and messages
  try {
    const token = await getMailTmToken(selectedEmail, password);
    const messages = await fetchMessages(token);
    if (messages.length === 0) {
      console.log(`No messages for ${selectedEmail}.`);
      return;
    }
    // Select message
    const msgOptions = messages.map(
      (m) => `${m.from.address}: ${m.subject.slice(0, 50)}`
    );
    const selectedMsgStr = (
      await $`printf '%s\n' ${msgOptions} | ${menuCommand} -p 'Select message:'`.text()
    ).trim();
    const selectedIndex = msgOptions.indexOf(selectedMsgStr);
    if (selectedIndex === -1) return;
    // Fetch and display
    const msg = await fetchMessage(token, messages[selectedIndex].id);
    console.log(`From: ${msg.from.address}`);
    console.log(`Subject: ${msg.subject}`);
    console.log(`Date: ${new Date(msg.createdAt).toLocaleString()}`);
    console.log("Body:");
    console.log(msg.text || msg.html?.replace(/<[^>]*>/g, "") || "No body.");
  } catch (error) {
    console.error("Failed to manage email:", error);
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
  let action = "copy";
  let actionCmd = options.copyCmd || (await getCopyCommand());
  if (options.typeCmd || options.autotype) {
    action = "type";
    actionCmd = options.typeCmd || (await getTypeCommand());
  }
  const passDir =
    process.env.PASSWORD_STORE_DIR || `${process.env.HOME}/.password-store`;
  // List entries
  const listOutput =
    await $`find ${passDir} -type f -name '*.gpg' -printf '%P\n' | sed 's/\\.gpg$//' | sort`.text();
  const entries = listOutput.trim().split("\n").filter(Boolean);
  // Special entries
  const specialEntries = ["Generate Credential", "Manage Temp Emails"];
  const displayEntries = [...specialEntries, ...entries];
  // Menu
  const menuCommand = await getMenuCommand();
  const selected = (
    await $`printf '%s\n' ${displayEntries} | ${menuCommand} -p 'Select:'`.text()
  ).trim();
  if (!selected) process.exit(0);
  // Handle special
  if (selected === "Generate Credential") {
    await generateCredential(menuCommand, passDir, action, actionCmd);
    process.exit(0);
  } else if (selected === "Manage Temp Emails") {
    await manageTempEmails(menuCommand, entries);
    process.exit(0);
  }
  // Regular pass handling (unchanged for brevity, but integrated)
  const content = await $`pass show ${selected}`.text();
  const lines = content.trim().split("\n");
  const password = lines[0]?.trim() || "";
  let fields: Record<string, string> = {};
  let hasOtpauth = false;
  for (let j = 1; j < lines.length; j++) {
    const line = lines[j]?.trim() || "";
    if (line.startsWith("otpauth://")) {
      hasOtpauth = true;
    } else if (line.includes(":")) {
      const [key, ...val] = line.split(":");
      fields[(key as string).trim().toLowerCase()] = val.join(":").trim();
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
      await $`printf '%s\n' ${fieldOptions} | ${menuCommand} -p 'Select field:'`.text()
    ).trim();
  }
  if (!selectedField) process.exit(0);
  let value = "";
  if (selectedField === "password") {
    value = password;
  } else if (selectedField === "otp") {
    value = (await $`pass otp ${selected}`.text()).trim();
  } else if (selectedField === "autotype") {
    // Autotype
    const username = fields["username"] || "";
    if (action === "type") {
      const copyCmd = await getCopyCommand();
      await $`echo -n ${password} | ${copyCmd}`;
      if (username) {
        await $`echo -n ${username} | ${actionCmd}`;
        const tabCmd = await getTabCommand();
        await $`${tabCmd}`;
      }
      await $`echo -n ${password} | ${actionCmd}`;
    } else {
      await $`echo -n ${password} | ${actionCmd}`;
    }
    process.exit(0);
  } else {
    value = fields[selectedField] || "";
  }
  // Perform action
  await $`echo -n ${value} | ${actionCmd}`;
  process.exit(0);
}
main().catch((error) => {
  console.error("Error:", error);
  process.exit(1);
});
