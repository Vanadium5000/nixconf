#!/usr/bin/env bun
/**
 * git-sync-debug.ts - Debug tool for git-sync authentication issues
 *
 * Tests the complete authentication chain:
 * - GPG agent connectivity
 * - SSH agent (via gpg-agent) status
 * - Pinentry GUI spawning capability
 * - Git SSH authentication to remotes
 *
 * Usage:
 *   git-sync-debug status      # Show all authentication status
 *   git-sync-debug gpg         # Test GPG agent
 *   git-sync-debug ssh         # Test SSH agent and keys
 *   git-sync-debug pinentry    # Test pinentry GUI spawning
 *   git-sync-debug git [repo]  # Test git fetch on a repo
 *   git-sync-debug fix         # Attempt to fix common issues
 *   git-sync-debug env         # Show relevant environment variables
 */

import { $ } from "bun";

// =============================================================================
// Types & Constants
// =============================================================================

interface TestResult {
  name: string;
  passed: boolean;
  message: string;
  details?: string;
}

const COLORS = {
  reset: "\x1b[0m",
  red: "\x1b[31m",
  green: "\x1b[32m",
  yellow: "\x1b[33m",
  blue: "\x1b[34m",
  cyan: "\x1b[36m",
  dim: "\x1b[2m",
  bold: "\x1b[1m",
};

// =============================================================================
// Utility Functions
// =============================================================================

function ok(msg: string): void {
  console.log(`${COLORS.green}✓${COLORS.reset} ${msg}`);
}

function fail(msg: string): void {
  console.log(`${COLORS.red}✗${COLORS.reset} ${msg}`);
}

function warn(msg: string): void {
  console.log(`${COLORS.yellow}!${COLORS.reset} ${msg}`);
}

function info(msg: string): void {
  console.log(`${COLORS.blue}→${COLORS.reset} ${msg}`);
}

function header(msg: string): void {
  console.log(`\n${COLORS.bold}${COLORS.cyan}═══ ${msg} ═══${COLORS.reset}\n`);
}

function dim(msg: string): string {
  return `${COLORS.dim}${msg}${COLORS.reset}`;
}

async function runCmd(
  cmd: string[],
  timeoutMs: number = 10000
): Promise<{ ok: boolean; stdout: string; stderr: string; code: number }> {
  try {
    const proc = Bun.spawn(cmd, {
      stdout: "pipe",
      stderr: "pipe",
    });

    const timeoutPromise = new Promise<never>((_, reject) => {
      setTimeout(() => reject(new Error("timeout")), timeoutMs);
    });

    const exitCode = await Promise.race([proc.exited, timeoutPromise]);
    const stdout = await new Response(proc.stdout).text();
    const stderr = await new Response(proc.stderr).text();

    return {
      ok: exitCode === 0,
      stdout: stdout.trim(),
      stderr: stderr.trim(),
      code: exitCode as number,
    };
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    return { ok: false, stdout: "", stderr: msg, code: -1 };
  }
}

// =============================================================================
// Test Functions
// =============================================================================

async function testGpgAgent(): Promise<TestResult[]> {
  const results: TestResult[] = [];

  // Test 1: GPG agent socket exists
  const socketPath =
    process.env.GNUPGHOME || `${process.env.HOME}/.gnupg`;
  const agentSocket = `${socketPath}/S.gpg-agent`;

  const socketExists = await Bun.file(agentSocket).exists();
  results.push({
    name: "GPG agent socket",
    passed: socketExists,
    message: socketExists ? "Socket exists" : "Socket not found",
    details: agentSocket,
  });

  // Test 2: GPG agent responds
  const agentTest = await runCmd([
    "gpg-connect-agent",
    "/bye",
  ]);
  results.push({
    name: "GPG agent connection",
    passed: agentTest.ok,
    message: agentTest.ok ? "Agent responding" : "Agent not responding",
    details: agentTest.stderr || agentTest.stdout,
  });

  // Test 3: GPG_TTY is set
  const gpgTty = process.env.GPG_TTY;
  results.push({
    name: "GPG_TTY environment",
    passed: !!gpgTty,
    message: gpgTty ? `Set to ${gpgTty}` : "Not set (pinentry may fail)",
  });

  // Test 4: Update startup TTY
  const updateTty = await runCmd([
    "gpg-connect-agent",
    "updatestartuptty",
    "/bye",
  ]);
  results.push({
    name: "Update startup TTY",
    passed: updateTty.ok,
    message: updateTty.ok ? "TTY updated" : "Failed to update TTY",
    details: updateTty.stderr,
  });

  return results;
}

async function testSshAgent(): Promise<TestResult[]> {
  const results: TestResult[] = [];

  // Test 1: SSH_AUTH_SOCK is set
  const sshSocket = process.env.SSH_AUTH_SOCK;
  results.push({
    name: "SSH_AUTH_SOCK environment",
    passed: !!sshSocket,
    message: sshSocket ? `Set to ${sshSocket}` : "Not set",
  });

  // Test 2: SSH agent socket exists (if set)
  if (sshSocket) {
    const socketExists = await Bun.file(sshSocket).exists();
    results.push({
      name: "SSH agent socket",
      passed: socketExists,
      message: socketExists ? "Socket exists" : "Socket not found",
      details: sshSocket,
    });
  }

  // Test 3: List SSH keys
  const sshList = await runCmd(["ssh-add", "-l"]);
  const hasKeys = sshList.ok && !sshList.stdout.includes("no identities");
  results.push({
    name: "SSH keys loaded",
    passed: hasKeys,
    message: hasKeys
      ? `Keys available`
      : sshList.code === 1
        ? "No keys loaded (may need unlock)"
        : "Agent not accessible",
    details: sshList.stdout || sshList.stderr,
  });

  // Test 4: Check if GPG agent is providing SSH
  const gpgSshSocket = `${process.env.GNUPGHOME || `${process.env.HOME}/.gnupg`}/S.gpg-agent.ssh`;
  const gpgSshExists = await Bun.file(gpgSshSocket).exists();
  const isGpgSsh = sshSocket?.includes("gpg-agent") || gpgSshExists;
  results.push({
    name: "GPG agent SSH support",
    passed: isGpgSsh,
    message: isGpgSsh
      ? "SSH via GPG agent (pinentry required for unlock)"
      : "Using standalone SSH agent",
    details: gpgSshSocket,
  });

  return results;
}

async function testPinentry(): Promise<TestResult[]> {
  const results: TestResult[] = [];

  // Test 1: DISPLAY/WAYLAND_DISPLAY set
  const waylandDisplay = process.env.WAYLAND_DISPLAY;
  const x11Display = process.env.DISPLAY;
  const hasDisplay = !!waylandDisplay || !!x11Display;
  results.push({
    name: "Display environment",
    passed: hasDisplay,
    message: hasDisplay
      ? `WAYLAND_DISPLAY=${waylandDisplay || "unset"}, DISPLAY=${x11Display || "unset"}`
      : "No display set (pinentry GUI will fail)",
  });

  // Test 2: XDG_RUNTIME_DIR set
  const xdgRuntime = process.env.XDG_RUNTIME_DIR;
  results.push({
    name: "XDG_RUNTIME_DIR",
    passed: !!xdgRuntime,
    message: xdgRuntime ? `Set to ${xdgRuntime}` : "Not set",
  });

  // Test 3: DBUS session available
  const dbusAddr = process.env.DBUS_SESSION_BUS_ADDRESS;
  results.push({
    name: "D-Bus session",
    passed: !!dbusAddr,
    message: dbusAddr ? "Session bus available" : "Not set (some pinentry features may fail)",
    details: dbusAddr,
  });

  // Test 4: Pinentry binary exists
  const pinentryTest = await runCmd(["which", "pinentry"]);
  results.push({
    name: "Pinentry binary",
    passed: pinentryTest.ok,
    message: pinentryTest.ok ? pinentryTest.stdout : "Not found in PATH",
  });

  // Test 5: Test pinentry can start (non-interactive)
  const pinentryStart = await runCmd(
    ["sh", "-c", "echo 'BYE' | pinentry"],
    5000
  );
  results.push({
    name: "Pinentry spawnable",
    passed: pinentryStart.ok || pinentryStart.stdout.includes("OK"),
    message:
      pinentryStart.ok || pinentryStart.stdout.includes("OK")
        ? "Pinentry can spawn"
        : "Pinentry failed to start",
    details: pinentryStart.stderr,
  });

  return results;
}

async function testGitRemote(repoPath?: string): Promise<TestResult[]> {
  const results: TestResult[] = [];

  const testPath = repoPath || process.cwd();

  // Test 1: Is it a git repo?
  const isRepo = await runCmd(["git", "rev-parse", "--git-dir"], 5000);
  if (!isRepo.ok) {
    results.push({
      name: "Git repository",
      passed: false,
      message: `Not a git repository: ${testPath}`,
    });
    return results;
  }
  results.push({
    name: "Git repository",
    passed: true,
    message: `Valid repo at ${testPath}`,
  });

  // Test 2: Get remote URL
  const remoteUrl = await runCmd(["git", "remote", "get-url", "origin"]);
  if (!remoteUrl.ok) {
    results.push({
      name: "Remote URL",
      passed: false,
      message: "No origin remote configured",
    });
    return results;
  }
  const url = remoteUrl.stdout;
  const isSsh = url.startsWith("git@") || url.includes("ssh://");
  results.push({
    name: "Remote URL",
    passed: true,
    message: `${isSsh ? "SSH" : "HTTPS"}: ${url}`,
  });

  // Test 3: Test SSH connection to remote host (if SSH)
  if (isSsh) {
    // Extract host from git@github.com:user/repo or ssh://git@github.com/...
    let host = "github.com";
    const atMatch = url.match(/@([^:\/]+)/);
    if (atMatch) host = atMatch[1];

    const sshTest = await runCmd(
      ["ssh", "-T", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", `git@${host}`],
      10000
    );
    // GitHub returns exit code 1 with "successfully authenticated" message
    const authSuccess =
      sshTest.stderr.includes("successfully authenticated") ||
      sshTest.stderr.includes("Welcome to") ||
      sshTest.ok;
    results.push({
      name: `SSH to ${host}`,
      passed: authSuccess,
      message: authSuccess ? "Authentication successful" : "Authentication failed",
      details: sshTest.stderr,
    });
  }

  // Test 4: Git fetch (dry run)
  const fetchTest = await runCmd(
    ["git", "fetch", "--dry-run", "origin"],
    30000
  );
  results.push({
    name: "Git fetch test",
    passed: fetchTest.ok,
    message: fetchTest.ok ? "Fetch would succeed" : "Fetch failed",
    details: fetchTest.stderr || fetchTest.stdout,
  });

  return results;
}

async function showEnvironment(): Promise<void> {
  header("Environment Variables");

  const vars = [
    "GPG_TTY",
    "SSH_AUTH_SOCK",
    "GNUPGHOME",
    "WAYLAND_DISPLAY",
    "DISPLAY",
    "XDG_RUNTIME_DIR",
    "DBUS_SESSION_BUS_ADDRESS",
    "HOME",
    "USER",
    "PATH",
  ];

  for (const v of vars) {
    const value = process.env[v];
    if (value) {
      // Truncate PATH for readability
      const display = v === "PATH" ? value.substring(0, 80) + "..." : value;
      console.log(`  ${COLORS.cyan}${v}${COLORS.reset}=${display}`);
    } else {
      console.log(`  ${COLORS.dim}${v}=${COLORS.reset}${COLORS.yellow}(unset)${COLORS.reset}`);
    }
  }
}

async function attemptFix(): Promise<void> {
  header("Attempting Fixes");

  // Fix 1: Set GPG_TTY
  info("Setting GPG_TTY...");
  const ttyResult = await runCmd(["tty"]);
  if (ttyResult.ok) {
    process.env.GPG_TTY = ttyResult.stdout;
    ok(`GPG_TTY set to ${ttyResult.stdout}`);
  } else {
    process.env.GPG_TTY = "/dev/pts/0";
    warn("Could not detect TTY, using /dev/pts/0");
  }

  // Fix 2: Update GPG agent TTY
  info("Updating GPG agent startup TTY...");
  const updateResult = await runCmd([
    "gpg-connect-agent",
    "updatestartuptty",
    "/bye",
  ]);
  if (updateResult.ok) {
    ok("GPG agent TTY updated");
  } else {
    fail(`Failed: ${updateResult.stderr}`);
  }

  // Fix 3: Restart gpg-agent if needed
  info("Reloading GPG agent...");
  const reloadResult = await runCmd([
    "gpg-connect-agent",
    "reloadagent",
    "/bye",
  ]);
  if (reloadResult.ok) {
    ok("GPG agent reloaded");
  } else {
    warn(`Reload returned: ${reloadResult.stderr}`);
  }

  // Fix 4: Try to add SSH key
  info("Checking SSH keys...");
  const sshList = await runCmd(["ssh-add", "-l"]);
  if (!sshList.ok || sshList.stdout.includes("no identities")) {
    info("Attempting to add default SSH key (may trigger pinentry)...");
    const addResult = await runCmd(["ssh-add"], 30000);
    if (addResult.ok) {
      ok("SSH key added");
    } else {
      warn(`ssh-add returned: ${addResult.stderr}`);
    }
  } else {
    ok("SSH keys already loaded");
  }

  console.log("");
  info("Fix attempt complete. Run 'git-sync-debug status' to verify.");
}

function printResults(results: TestResult[]): void {
  for (const r of results) {
    if (r.passed) {
      ok(`${r.name}: ${r.message}`);
    } else {
      fail(`${r.name}: ${r.message}`);
    }
    if (r.details) {
      console.log(`    ${dim(r.details)}`);
    }
  }
}

async function runAllTests(repoPath?: string): Promise<void> {
  let allPassed = true;

  header("GPG Agent");
  const gpgResults = await testGpgAgent();
  printResults(gpgResults);
  if (gpgResults.some((r) => !r.passed)) allPassed = false;

  header("SSH Agent");
  const sshResults = await testSshAgent();
  printResults(sshResults);
  if (sshResults.some((r) => !r.passed)) allPassed = false;

  header("Pinentry (GUI)");
  const pinentryResults = await testPinentry();
  printResults(pinentryResults);
  if (pinentryResults.some((r) => !r.passed)) allPassed = false;

  header("Git Remote");
  const gitResults = await testGitRemote(repoPath);
  printResults(gitResults);
  if (gitResults.some((r) => !r.passed)) allPassed = false;

  header("Summary");
  if (allPassed) {
    ok("All tests passed! Git-sync should work correctly.");
  } else {
    fail("Some tests failed. Run 'git-sync-debug fix' to attempt repairs.");
    console.log("");
    info("Common fixes:");
    console.log("  1. Ensure you're in a graphical session (Hyprland/Wayland)");
    console.log("  2. Run: gpg-connect-agent updatestartuptty /bye");
    console.log("  3. Run: ssh-add (to unlock SSH key via pinentry)");
    console.log("  4. Check: systemctl --user status gpg-agent");
  }
}

// =============================================================================
// Main
// =============================================================================

async function main(): Promise<void> {
  const args = Bun.argv.slice(2);
  const command = args[0] || "status";

  console.log(`${COLORS.bold}git-sync-debug${COLORS.reset} - Authentication diagnostics\n`);

  switch (command) {
    case "status":
    case "all":
      await runAllTests(args[1]);
      break;

    case "gpg":
      header("GPG Agent Tests");
      printResults(await testGpgAgent());
      break;

    case "ssh":
      header("SSH Agent Tests");
      printResults(await testSshAgent());
      break;

    case "pinentry":
      header("Pinentry Tests");
      printResults(await testPinentry());
      break;

    case "git":
      header("Git Remote Tests");
      if (args[1]) {
        process.chdir(args[1]);
      }
      printResults(await testGitRemote());
      break;

    case "fix":
      await attemptFix();
      break;

    case "env":
      await showEnvironment();
      break;

    case "help":
    case "--help":
    case "-h":
      console.log(`Usage: git-sync-debug <command> [options]

Commands:
  status [repo]   Run all tests (default)
  gpg             Test GPG agent connectivity
  ssh             Test SSH agent and loaded keys
  pinentry        Test pinentry GUI spawning capability
  git [repo]      Test git fetch on repository
  fix             Attempt to fix common issues
  env             Show relevant environment variables
  help            Show this help

Examples:
  git-sync-debug                           # Run all tests in current dir
  git-sync-debug status ~/.password-store  # Test specific repo
  git-sync-debug fix                       # Try to fix issues
  git-sync-debug ssh                       # Just test SSH

For systemd service debugging:
  systemctl --user status git-sync-*
  journalctl --user -u git-sync-passwords -f
`);
      break;

    default:
      fail(`Unknown command: ${command}`);
      console.log("Run 'git-sync-debug help' for usage.");
      process.exit(1);
  }
}

main().catch((error) => {
  console.error(`${COLORS.red}Error:${COLORS.reset}`, error.message);
  process.exit(1);
});
