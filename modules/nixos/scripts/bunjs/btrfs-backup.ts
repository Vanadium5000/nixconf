#!/usr/bin/env bun
// btrfs-backup.ts - BunJS BTRFS backup TUI for NixOS impermanence systems
import { $ } from "bun";
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";

// ============================================================================
// Configuration
// ============================================================================
const CONFIG = {
  DEVICE_KEY_PATH: "/persist/device-key",
  LOCAL_PERSIST_PATH: "/persist",
  LOCAL_CACHE_PATH: "/persist/cache",
  REMOTE_BACKUPS_DIR: "Backups",
  SNAPSHOT_TMP_DIR: "/persist/.backup-snapshots",
  SAFETY_COUNTDOWN_SECONDS: 5,
} as const;

// ============================================================================
// Types
// ============================================================================
interface BtrfsPartition {
  name: string;
  path: string;
  uuid: string;
  label: string | null;
  size: string;
  mountpoint: string | null;
  fstype: string;
}

interface BackupContext {
  deviceKey: string;
  targetPartition: BtrfsPartition;
  mountPoint: string;
  backupDir: string;
  dateStr: string;
  wasAlreadyMounted: boolean;
}

// ============================================================================
// Logging & Notifications
// ============================================================================
function log(level: string, message: string, ...args: any[]) {
  const timestamp = new Date().toISOString();
  const prefix =
    level === "ERROR" ? "\x1b[31m" : level === "WARN" ? "\x1b[33m" : "\x1b[36m";
  console.log(`${prefix}[${timestamp}] [${level}]\x1b[0m ${message}`, ...args);
}

function logInfo(message: string, ...args: any[]) {
  log("INFO", message, ...args);
}

function logWarn(message: string, ...args: any[]) {
  log("WARN", message, ...args);
}

function logError(message: string, ...args: any[]) {
  log("ERROR", message, ...args);
}

async function notify(message: string, title: string = "btrfs-backup") {
  console.log(`[${title}] ${message}`);
  try {
    await $`notify-send -t 5000 "${title}" "${message}"`.quiet();
  } catch {
    logError(`Failed to send notification: ${message}`);
  }
}

// ============================================================================
// Utility Functions
// ============================================================================
async function commandExists(cmd: string): Promise<boolean> {
  try {
    const result = await $`which ${cmd}`.quiet();
    return result.exitCode === 0;
  } catch {
    return false;
  }
}

async function getMenuCommand(): Promise<string[]> {
  if (await commandExists("rofi")) {
    return ["rofi", "-dmenu", "-i"];
  } else if (process.env.WAYLAND_DISPLAY && (await commandExists("wofi"))) {
    return ["wofi", "--show", "dmenu"];
  } else {
    throw new Error("Neither rofi nor wofi found. Cannot display TUI.");
  }
}

async function selectOption(
  menuCommand: string[],
  options: string[],
  prompt: string,
  message?: string
): Promise<string> {
  if (options.length === 0) return "";
  try {
    const mesgArg = message ? ["-mesg", message] : [];
    const selected = (
      await $`printf '%s\n' ${options} | ${menuCommand} -p ${prompt} ${mesgArg}`.text()
    ).trim();
    return selected;
  } catch {
    // User cancelled
    return "";
  }
}

async function confirmAction(
  menuCommand: string[],
  prompt: string,
  message?: string
): Promise<boolean> {
  const options = ["Yes, proceed", "No, cancel"];
  const selected = await selectOption(menuCommand, options, prompt, message);
  return selected === "Yes, proceed";
}

function generateRandomChars(length: number = 8): string {
  return crypto
    .randomBytes(length / 2 + 1)
    .toString("hex")
    .slice(0, length);
}

// ============================================================================
// Permission & Environment Checks
// ============================================================================
function checkRootPermissions(): void {
  if (process.getuid?.() !== 0) {
    logError("This script must be run as root!");
    logError("Use: sudo btrfs-backup");
    process.exit(1);
  }
}

function getHostname(): string {
  const host = process.env.HOST;
  if (!host) {
    logError("HOST environment variable is not set!");
    logError("");
    logError(
      "The HOST variable should be set to your NixOS configuration name."
    );
    logError(
      "This is typically set in your NixOS configuration or shell profile."
    );
    logError("");
    logError("To fix this:");
    logError("  1. Add 'HOST=<your-config-name>' to your environment");
    logError("  2. Or run: HOST=<your-config-name> sudo -E btrfs-backup");
    logError("");
    process.exit(1);
  }
  return host;
}

// ============================================================================
// Device Key Management
// ============================================================================
function loadOrGenerateDeviceKey(): string {
  const keyPath = CONFIG.DEVICE_KEY_PATH;

  if (fs.existsSync(keyPath)) {
    const key = fs.readFileSync(keyPath, "utf-8").trim();
    logInfo(`Loaded existing device key: ${key}`);
    return key;
  }

  // Generate new key
  const hostname = getHostname();
  const randomPart = generateRandomChars(8);
  const deviceKey = `${hostname}-${randomPart}`;

  // Ensure parent directory exists
  const parentDir = path.dirname(keyPath);
  if (!fs.existsSync(parentDir)) {
    fs.mkdirSync(parentDir, { recursive: true, mode: 0o700 });
  }

  // Write key with secure permissions
  fs.writeFileSync(keyPath, deviceKey + "\n", { mode: 0o600 });
  logInfo(`Generated new device key: ${deviceKey}`);

  return deviceKey;
}

// ============================================================================
// BTRFS Partition Discovery
// ============================================================================
async function listBtrfsPartitions(): Promise<BtrfsPartition[]> {
  try {
    const result =
      await $`lsblk -o NAME,UUID,FSTYPE,LABEL,SIZE,MOUNTPOINT -J`.json();
    const partitions: BtrfsPartition[] = [];

    function processDevice(device: any, parentPath: string = "/dev") {
      const devPath = `${parentPath}/${device.name}`;

      if (device.fstype === "btrfs" && device.uuid) {
        partitions.push({
          name: device.name,
          path: devPath,
          uuid: device.uuid,
          label: device.label || null,
          size: device.size,
          mountpoint: device.mountpoint || null,
          fstype: device.fstype,
        });
      }

      // Process children (partitions)
      if (device.children) {
        for (const child of device.children) {
          processDevice(child, parentPath);
        }
      }
    }

    for (const device of result.blockdevices || []) {
      processDevice(device);
    }

    // Filter out the root/persist partition (don't backup to yourself)
    const rootUuid = await getRootBtrfsUuid();
    return partitions.filter((p) => p.uuid !== rootUuid);
  } catch (error) {
    logError("Failed to list BTRFS partitions:", error);
    return [];
  }
}

async function getRootBtrfsUuid(): Promise<string | null> {
  try {
    const result = await $`findmnt -n -o UUID /persist`.text();
    return result.trim() || null;
  } catch {
    return null;
  }
}

// ============================================================================
// Mount Management
// ============================================================================
async function ensureMounted(
  partition: BtrfsPartition
): Promise<{ mountPoint: string; wasAlreadyMounted: boolean }> {
  if (partition.mountpoint) {
    return { mountPoint: partition.mountpoint, wasAlreadyMounted: true };
  }

  // Create temporary mount point
  const mountPoint = `/tmp/btrfs-backup-${partition.uuid.slice(0, 8)}`;
  if (!fs.existsSync(mountPoint)) {
    fs.mkdirSync(mountPoint, { recursive: true, mode: 0o700 });
  }

  logInfo(`Mounting ${partition.path} to ${mountPoint}...`);
  const result = await $`mount ${partition.path} ${mountPoint}`.quiet();
  if (result.exitCode !== 0) {
    throw new Error(`Failed to mount ${partition.path}`);
  }

  return { mountPoint, wasAlreadyMounted: false };
}

async function unmountIfNeeded(
  mountPoint: string,
  wasAlreadyMounted: boolean
): Promise<void> {
  if (wasAlreadyMounted) {
    logInfo(`Leaving ${mountPoint} mounted (was already mounted)`);
    return;
  }

  logInfo(`Unmounting ${mountPoint}...`);
  try {
    await $`sync`.quiet();
    await $`umount ${mountPoint}`.quiet();
    fs.rmdirSync(mountPoint);
  } catch (error) {
    logWarn(`Failed to unmount ${mountPoint}:`, error);
  }
}

// ============================================================================
// Backup Directory Initialization
// ============================================================================
async function checkAndInitializeBackupDir(
  menuCommand: string[],
  partition: BtrfsPartition,
  mountPoint: string
): Promise<boolean> {
  const backupsPath = path.join(mountPoint, CONFIG.REMOTE_BACKUPS_DIR);

  if (fs.existsSync(backupsPath)) {
    logInfo(`Backup directory exists: ${backupsPath}`);
    return true;
  }

  // Show warning and device info
  const warningMessage = `⚠️  BACKUP DIRECTORY NOT FOUND

Device: ${partition.label || partition.name}
Path: ${partition.path}
UUID: ${partition.uuid}
Size: ${partition.size}
Filesystem: ${partition.fstype}

This partition will be initialized with a /${
    CONFIG.REMOTE_BACKUPS_DIR
  } directory.
A ${CONFIG.SAFETY_COUNTDOWN_SECONDS}-second safety countdown will begin.`;

  logWarn("Backup directory not found on target partition!");
  console.log("\n" + "=".repeat(60));
  console.log(warningMessage);
  console.log("=".repeat(60) + "\n");

  // Confirm with user via TUI
  const confirmed = await confirmAction(
    menuCommand,
    "Initialize backup directory?",
    warningMessage
  );

  if (!confirmed) {
    logInfo("User cancelled initialization");
    return false;
  }

  // Safety countdown
  console.log("\n⏳ Safety countdown - press Ctrl+C to cancel:\n");
  for (let i = CONFIG.SAFETY_COUNTDOWN_SECONDS; i > 0; i--) {
    const bar =
      "█".repeat(CONFIG.SAFETY_COUNTDOWN_SECONDS - i + 1) + "░".repeat(i - 1);
    process.stdout.write(`\r  [${bar}] ${i} seconds remaining...`);
    await Bun.sleep(1000);
  }
  console.log("\n");

  // Create backup directory
  fs.mkdirSync(backupsPath, { recursive: true, mode: 0o755 });
  logInfo(`Created backup directory: ${backupsPath}`);
  await notify("Initialized backup directory on external drive");

  return true;
}

// ============================================================================
// Snapshot & Backup Operations
// ============================================================================
async function createLocalSnapshot(
  deviceKey: string,
  dateStr: string
): Promise<string> {
  const snapshotDir = CONFIG.SNAPSHOT_TMP_DIR;
  const snapshotName = `backup-${dateStr}`;
  const snapshotPath = path.join(snapshotDir, snapshotName);

  // Ensure snapshot directory exists
  if (!fs.existsSync(snapshotDir)) {
    fs.mkdirSync(snapshotDir, { recursive: true, mode: 0o700 });
  }

  // Remove existing snapshot with same name if it exists
  if (fs.existsSync(snapshotPath)) {
    logWarn(`Removing existing snapshot: ${snapshotPath}`);
    await $`btrfs subvolume delete ${snapshotPath}`.quiet();
  }

  // Create writable snapshot first (we need to modify it to exclude cache)
  logInfo(`Creating snapshot of ${CONFIG.LOCAL_PERSIST_PATH}...`);
  const result =
    await $`btrfs subvolume snapshot ${CONFIG.LOCAL_PERSIST_PATH} ${snapshotPath}`.quiet();

  if (result.exitCode !== 0) {
    throw new Error("Failed to create local snapshot");
  }

  // Delete the cache subvolume from the snapshot to exclude it from backup
  const cacheInSnapshot = path.join(snapshotPath, "cache");
  if (fs.existsSync(cacheInSnapshot)) {
    logInfo(`Excluding cache directory from backup...`);
    try {
      // Check if it's a subvolume
      const inoResult = await $`stat -c %i ${cacheInSnapshot}`.text();
      const inode = parseInt(inoResult.trim(), 10);

      if (inode === 256) {
        // It's a subvolume, delete it
        await $`btrfs subvolume delete ${cacheInSnapshot}`.quiet();
        logInfo(`Removed cache subvolume from snapshot`);
      } else {
        // It's a regular directory, remove it recursively
        await $`rm -rf ${cacheInSnapshot}`.quiet();
        logInfo(`Removed cache directory from snapshot`);
      }
    } catch (error) {
      logWarn(`Could not remove cache from snapshot: ${error}`);
    }
  }

  // Now make the snapshot read-only for sending
  logInfo(`Setting snapshot to read-only...`);
  const roResult =
    await $`btrfs property set -ts ${snapshotPath} ro true`.quiet();
  if (roResult.exitCode !== 0) {
    throw new Error("Failed to set snapshot to read-only");
  }

  logInfo(`Created snapshot: ${snapshotPath}`);
  return snapshotPath;
}

async function findPreviousBackup(
  deviceBackupDir: string
): Promise<string | null> {
  if (!fs.existsSync(deviceBackupDir)) {
    return null;
  }

  const entries = fs.readdirSync(deviceBackupDir);
  const backups = entries
    .filter((e) => fs.statSync(path.join(deviceBackupDir, e)).isDirectory())
    .sort()
    .reverse();

  if (backups.length > 0) {
    return path.join(deviceBackupDir, backups[0]!);
  }

  return null;
}

async function findPreviousLocalSnapshot(): Promise<string | null> {
  const snapshotDir = CONFIG.SNAPSHOT_TMP_DIR;

  if (!fs.existsSync(snapshotDir)) {
    return null;
  }

  const entries = fs.readdirSync(snapshotDir);
  const snapshots = entries
    .filter((e) => e.startsWith("backup-"))
    .sort()
    .reverse();

  // Return second most recent (the most recent is the current one)
  if (snapshots.length > 1) {
    return path.join(snapshotDir, snapshots[1]!);
  }

  return null;
}

async function performBackup(
  snapshotPath: string,
  deviceBackupDir: string,
  dateStr: string
): Promise<void> {
  const targetPath = path.join(deviceBackupDir, dateStr);

  // Ensure device backup directory exists
  if (!fs.existsSync(deviceBackupDir)) {
    fs.mkdirSync(deviceBackupDir, { recursive: true, mode: 0o755 });
  }

  // Find parent snapshot for incremental backup
  const parentSnapshot = await findPreviousLocalSnapshot();
  const previousRemoteBackup = await findPreviousBackup(deviceBackupDir);

  if (parentSnapshot && previousRemoteBackup) {
    // Incremental backup
    logInfo(`Performing incremental backup...`);
    logInfo(`  Parent snapshot: ${parentSnapshot}`);
    logInfo(`  Target: ${targetPath}`);

    const sendCmd = $`btrfs send -p ${parentSnapshot} ${snapshotPath}`;
    const recvCmd = $`btrfs receive ${deviceBackupDir}`;

    // Pipe send to receive
    const result =
      await $`btrfs send -p ${parentSnapshot} ${snapshotPath} | btrfs receive ${deviceBackupDir}`;

    if (result.exitCode !== 0) {
      throw new Error("Incremental backup failed");
    }
  } else {
    // Full backup
    logInfo(`Performing full backup (no previous backup found)...`);
    logInfo(`  Source: ${snapshotPath}`);
    logInfo(`  Target: ${targetPath}`);

    const result =
      await $`btrfs send ${snapshotPath} | btrfs receive ${deviceBackupDir}`;

    if (result.exitCode !== 0) {
      throw new Error("Full backup failed");
    }
  }

  logInfo(`Backup completed: ${targetPath}`);
}

async function cleanupOldSnapshots(keepCount: number = 3): Promise<void> {
  const snapshotDir = CONFIG.SNAPSHOT_TMP_DIR;

  if (!fs.existsSync(snapshotDir)) {
    return;
  }

  const entries = fs.readdirSync(snapshotDir);
  const snapshots = entries
    .filter((e) => e.startsWith("backup-"))
    .sort()
    .reverse();

  // Keep the most recent snapshots
  const toDelete = snapshots.slice(keepCount);

  for (const snapshot of toDelete) {
    const snapshotPath = path.join(snapshotDir, snapshot);
    logInfo(`Cleaning up old snapshot: ${snapshotPath}`);
    try {
      await $`btrfs subvolume delete ${snapshotPath}`.quiet();
    } catch (error) {
      logWarn(`Failed to delete snapshot ${snapshotPath}:`, error);
    }
  }
}

// ============================================================================
// TUI Display Helpers
// ============================================================================
function formatPartitionOption(partition: BtrfsPartition): string {
  const label = partition.label || partition.name;
  const mountStatus = partition.mountpoint
    ? `📁 ${partition.mountpoint}`
    : "💿 Not mounted";
  return `${label} (${partition.size}) - ${mountStatus}`;
}

function buildInfoMessage(deviceKey: string, dateStr: string): string {
  return `━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
BTRFS Backup - ${deviceKey}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📂 Source: /persist (excluding cache)
📁 Destination: /Backups/${deviceKey}/${dateStr}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`;
}

// ============================================================================
// Main Entry Point
// ============================================================================
async function main() {
  const args = Bun.argv.slice(2);
  const dryRun = args.includes("--dry-run");
  const testKeygen = args.includes("--test-keygen");

  console.log("\n🔒 BTRFS Backup for NixOS Impermanence\n");

  // Test keygen mode
  if (testKeygen) {
    const key = loadOrGenerateDeviceKey();
    console.log(`Device key: ${key}`);
    process.exit(0);
  }

  // Check permissions
  checkRootPermissions();

  // Load or generate device key
  const deviceKey = loadOrGenerateDeviceKey();
  // Use full timestamp to allow multiple backups per day
  const now = new Date();
  const dateStr = now.toISOString().replace(/[:.]/g, "-").slice(0, 19); // YYYY-MM-DDTHH-MM-SS

  // Get menu command
  const menuCommand = await getMenuCommand();

  // List available BTRFS partitions
  logInfo("Scanning for BTRFS partitions...");
  const partitions = await listBtrfsPartitions();

  if (partitions.length === 0) {
    await notify("No external BTRFS partitions found!", "btrfs-backup");
    logError(
      "No external BTRFS partitions found. Please connect a BTRFS-formatted drive."
    );
    process.exit(1);
  }

  // Build info message
  const infoMessage = buildInfoMessage(deviceKey, dateStr);

  // Let user select partition
  const partitionOptions = partitions.map(formatPartitionOption);
  partitionOptions.push("❌ Cancel");

  const selected = await selectOption(
    menuCommand,
    partitionOptions,
    "Select backup target",
    infoMessage
  );

  if (!selected || selected === "❌ Cancel") {
    logInfo("Backup cancelled by user");
    process.exit(0);
  }

  // Find selected partition
  const selectedIndex = partitionOptions.indexOf(selected);
  const targetPartition = partitions[selectedIndex];

  if (!targetPartition) {
    logError("Invalid partition selection");
    process.exit(1);
  }

  logInfo(
    `Selected partition: ${targetPartition.path} (${
      targetPartition.label || targetPartition.name
    })`
  );

  if (dryRun) {
    console.log("\n[DRY RUN] Would perform backup:");
    console.log(`  Source: ${CONFIG.LOCAL_PERSIST_PATH}`);
    console.log(
      `  Target: ${targetPartition.path}/${CONFIG.REMOTE_BACKUPS_DIR}/${deviceKey}/${dateStr}`
    );
    console.log("  (No changes made)");
    process.exit(0);
  }

  try {
    // Mount partition if needed
    const { mountPoint, wasAlreadyMounted } = await ensureMounted(
      targetPartition
    );
    logInfo(`Mount point: ${mountPoint}`);

    // Check and initialize backup directory
    const initialized = await checkAndInitializeBackupDir(
      menuCommand,
      targetPartition,
      mountPoint
    );
    if (!initialized) {
      await unmountIfNeeded(mountPoint, wasAlreadyMounted);
      process.exit(0);
    }

    // Create local snapshot
    const snapshotPath = await createLocalSnapshot(deviceKey, dateStr);

    // Perform backup
    const deviceBackupDir = path.join(
      mountPoint,
      CONFIG.REMOTE_BACKUPS_DIR,
      deviceKey
    );
    await performBackup(snapshotPath, deviceBackupDir, dateStr);

    // Cleanup old snapshots (keep last 3)
    await cleanupOldSnapshots(3);

    // Unmount if we mounted it
    await unmountIfNeeded(mountPoint, wasAlreadyMounted);

    // Success notification
    await notify(
      `Backup completed successfully!\n${deviceKey}/${dateStr}`,
      "btrfs-backup"
    );
    console.log("\n✅ Backup completed successfully!\n");
  } catch (error) {
    logError("Backup failed:", error);
    await notify(`Backup failed: ${error}`, "btrfs-backup");
    process.exit(1);
  }
}

main().catch(async (error) => {
  console.error("Fatal error:", error);
  await notify("Backup script crashed", "btrfs-backup");
  process.exit(1);
});
