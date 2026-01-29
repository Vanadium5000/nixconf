# AGENTS.md - NixOS Configuration Repository

> **NEVER RUN REBUILD COMMANDS FOR THE USER. DO NOT EXECUTE `./rebuild.sh`,
> `nixos-rebuild`, OR ANY VARIANT. THE USER WILL REBUILD MANUALLY.**

## Coding Standards

All code contributions must adhere to the following engineering standards:

### Modularisation

- **Single Responsibility**: Each module/file should do one thing well.
- **Composability**: Modules should be independently importable and composable.
- **Encapsulation**: Internal implementation details should not leak; expose
  clean interfaces via `options`.
- **Directory Structure**: Group related functionality in directories; use
  `import-tree` for automatic loading.

### Technical Inline Commenting

**PRESERVE ALL EXISTING COMMENTS. NEVER remove comments unless explicitly
asked. Comments are documentation, not noise.**

#### What to Comment

- **Units and meanings**: `timeout = 3000; # 3s timeout` — the number alone
  doesn't convey the unit or why that value was chosen.
- **Non-obvious values**: `cache_size = 4096; # Number of cached entries` —
  clarifies what the number represents.
- **Format explanations**: `"[::1]:53" # IPv6 loopback listener` — not everyone
  knows IPv6 notation.
- **Rationale**: Why a decision was made, especially for workarounds.
- **Edge cases**: Hardware quirks, upstream bugs, NixOS-specific gotchas.
- **References**: Links to issues, docs, or discussions for workarounds.
- **Module headers**: Brief description of purpose and dependencies.

#### What NOT to Comment

- **Tautologies**: `enable = true; # Enable the service` — the code is
  self-explanatory.
- **Obvious operations**: `# Import the package` above an import statement.

#### Examples

```nix
# BAD - tautology, says what the code literally does
virtualisation.docker.enable = true; # Enable docker

# GOOD - explains the unit/meaning of a magic number
timeout = 3000; # 3s (reduced from 5s for faster fallback)

# GOOD - explains what a cryptic value means
listen_addresses = [
  "127.0.0.1:53"
  "[::1]:53" # IPv6 loopback listener
];

# GOOD - explains WHY, not what
macAddress = "stable"; # "random" breaks captive portals on reconnect
```

### DRY (Don't Repeat Yourself)

- **Extract Common Patterns**: Use `self.lib` for reusable functions
  (persistence helpers, generators, etc.).
- **Centralise Configuration**: Use `config.preferences` for values referenced
  in multiple places.
- **Avoid Copy-Paste**: If the same logic appears twice, extract it into a
  function or module.
- **Use `mkMerge` and `mkIf`**: Compose conditional configurations cleanly
  rather than duplicating blocks.

### Code Quality

- **Type Safety**: Use `lib.types` for all option definitions; be specific
  (e.g., `types.port` not `types.int`).
- **Fail Fast**: Use `lib.assertMsg` for configuration validation; catch errors
  at eval time, not runtime.
- **Idempotency**: Modules should produce identical results on repeated
  evaluations.
- **Minimal Dependencies**: Import only what's needed; prefer `inherit` for
  selective imports.

---

This is a NixOS configuration flake using `flake-parts` and `import-tree` for
modular system configuration. It relies on `path:.` for flake operations to
include gitignored files (like `secrets.nix`).

## Repository Structure

```text
nixconf/
├── flake.nix           # Main flake definition
├── rebuild.sh          # System rebuild script (wraps nixos-rebuild)
├── secrets.nix         # Auto-generated secrets (gitignored)
├── modules/
│   ├── common/         # Shared base modules (impermanence, networking)
│   ├── hosts/          # Per-machine configs (legion5i, macbook, ionos_vps)
│   ├── nixos/          # NixOS-specific modules (desktop, terminal, scripts)
│   ├── programmes/     # Application configurations
│   ├── hjem/           # User environment (custom home-manager alternative)
│   ├── lib/            # Custom library functions (via self.lib)
│   ├── _pkgs/          # Custom package definitions (via self.packages)
│   └── theme.nix       # Theme definitions (via self.theme/self.colors)
```

## Build Commands

**Crucial:** Always use `path:.` when referring to the flake to ensure
gitignored files (like `secrets.nix`) are included in the build source.

```bash
# Build and switch (most common)
HOST=legion5i ./rebuild.sh switch

# Build without switching (good for testing)
HOST=macbook ./rebuild.sh build

# Dry-run to preview changes
HOST=legion5i ./rebuild.sh dry-run

# Validate flake before switching (runs nix flake check)
HOST=legion5i ./rebuild.sh --validate switch

# Deploy to remote host
HOST=ionos_vps ./rebuild.sh deploy root@host

# Install on new machine (via nixos-anywhere)
HOST=macbook ./rebuild.sh install root@192.168.1.100

# Rollback
HOST=legion5i ./rebuild.sh rollback

# Show generations
HOST=legion5i ./rebuild.sh generations
```

## Linting and Formatting

We use `nixfmt-rfc-style` for formatting. **Do not use alejandra.**

```bash
# Format all Nix files (Required)
nixfmt .

# Format single file
nixfmt path/to/file.nix

# Linting
statix check .   # Check for issues
statix fix .     # Auto-fix issues
```

## Code Style & Conventions

### Module Structure

Modules follow the `flake-parts` pattern. Use `import-tree` for directory
structures.

```nix
{ self, inputs, ... }:
{
  flake.nixosModules.my-module = { pkgs, config, lib, ... }:
    let
      inherit (lib) mkOption mkIf types;
      cfg = config.preferences.my-module;
    in
    {
      options.preferences.my-module = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Enable my-module functionality";
        };
      };

      config = mkIf cfg.enable {
        # Config implementation
      };
    };
}
```

### Preferences System (`config.preferences`)

The configuration is controlled via a centralized `preferences` option tree
(defined in `modules/common/base.nix`).

- `preferences.enable`: Global enable flag (default true).
- `preferences.hostName`: Machine hostname.
- `preferences.user.username`: Main user's username.
- `preferences.user.extraGroups`: Additional groups for the user.
- `preferences.system.backlightDevice`: Hardware ID for backlight.
- `preferences.allowedUnfree`: List of allowed unfree packages.
- `preferences.autostart`: List of packages/commands to autostart.

**Usage:**
Use `config.preferences.user.username` instead of hardcoding "matrix".

### Custom Packages (`_pkgs`)

Packages in `modules/_pkgs/` are automatically exposed via `self.packages`.

- File name must match the package name (e.g., `daisyui-mcp.nix`).
- Do not create a `default.nix` in `_pkgs/`.

```nix
# modules/_pkgs/my-tool.nix
{ pkgs, ... }:
pkgs.stdenv.mkDerivation {
  pname = "my-tool";
  version = "1.0";
  # ...
}
```

### Custom Library (`modules/lib`)

Accessible via `self.lib`. Contains helpers for persistence and config
generation.

```nix
# Import lib functions
inherit (self.lib.persistence) mkPersistent;
inherit (self.lib.generators) toHyprconf;

# Usage
file = mkPersistent {
  user = config.preferences.user.username;
  fileName = "settings.json";
  targetFile = "/home/user/.config/app/settings.json";
};
```

### Formatting Rules

- **Formatter:** `nixfmt` (RFC style).
- **Indentation:** 2 spaces.
- **Lists:** Single-item lists on one line, multi-item lists = one per line.
- **Imports:** Grouped at the top of the `let` block or `imports` list.

## Design System: Liquid Glass

We implement the **Liquid Glass** design language (based on Apple's iOS 26 /
macOS Tahoe) adapted for a Cyberpunk Electric Dark palette.

### Core Principles

- **Materiality**: Surfaces behave like physical glass.
- **Depth**: Layered transparency (Blur ≤ 60px, Opacity 10-25%).
- **Light**: Specular highlights and gradients.

### Design Tokens (Cyberpunk Electric Dark)

- **Background**: `#000000` (Main), `#141420` (Alt)
- **Accent**: `#5454fc` (Primary), `#54fcfc` (Active)
- **Glass**: `rgba(8,8,12,0.75)` with 8px blur.
- **Typography**: JetBrainsMono Nerd Font.

See `modules/LIQUID_GLASS_SPEC.md` for the full specification.

## Impermanence & Persistence

This system uses ephemeral root storage. You **MUST** explicitly persist
files/directories that should survive a reboot.

### Critical Data (Backed up)

Use `impermanence.nixos` (system) or `impermanence.home` (user).

**Guidelines:**

- Add directories containing configuration, database files, or keys.
- Add specific files if the parent directory shouldn't be persisted.

```nix
# System Persistence
impermanence.nixos.directories = [
  "/var/lib/nixos"
  "/var/lib/bluetooth"
];
impermanence.nixos.files = [
  "/etc/machine-id"
];

# User Persistence
impermanence.home.directories = [
  "Documents"
  "nixconf"
  ".ssh"
  ".config/obsidian"
];
impermanence.home.files = [
  ".zsh_history"
];
```

### Cache / Large Data (Not Backed Up)

Use `impermanence.*.cache` for large files or download artifacts (>50MB) that
can be re-downloaded or regenerated. Cache directories are persisted across
reboots just like regular persistence, but are **not included in backups**.
They are never automatically cleaned up - the only difference is backup
inclusion.

```nix
# System Cache
impermanence.nixos.cache.directories = [
  "/var/cache/ollama" # Large AI models
];

# User Cache
impermanence.home.cache.directories = [
  ".cache/mozilla"
  ".cache/spotify"
  "Downloads"       # Large downloads
  ".local/share/Steam" # Game files
];
```

## Flake & Advanced Patterns

### Self-References

Access flake outputs directly via `self`:

- `self.nixosModules.*`: Access other modules.
- `self.packages.${pkgs.stdenv.hostPlatform.system}.*`: Access custom packages.
- `self.theme`: Access the global theme definition.
- `self.colors`: Access the generated color palette.
- `self.secrets`: Access runtime secrets (loaded via `rebuild.sh`).

### Secrets Management

Secrets are managed via `pass` (password-store) and `secrets.nix`.

1. `rebuild.sh` reads secrets from `pass` based on `SECRETS_MAP`.
2. It generates `secrets.nix` (ignored by git).
3. `flake.nix` imports `secrets.nix` and exposes `self.secrets`.
4. Modules access secrets via `self.secrets.SECRET_NAME`.

**Note:** Never commit actual secrets. `secrets.nix` is in `.gitignore`.

### CUDA & Environment Variables

When implementing modules that require CUDA, follow these patterns:

1. **Check `config.nixpkgs.config.cudaSupport`** to conditionally enable
   features or variables.
2. **Set Environment Variables** in `environment.variables` if needed for
   python libraries or binaries to find CUDA libs:

```nix
environment.variables = lib.mkIf (config.nixpkgs.config.cudaSupport or false) {
  USE_CUDA = "1";
  CUDA_PATH = "${pkgs.cudatoolkit}";
  LD_LIBRARY_PATH =
    "${pkgs.cudatoolkit}/lib:${pkgs.cudaPackages.cudnn}/lib"
    + (lib.optionalString (config.hardware ? nvidia)
        ":${config.hardware.nvidia.package}/lib")
    + ":$LD_LIBRARY_PATH";
};
```

### Input Handling

- Use `inputs.nixpkgs.lib` for standard library functions.
- Use `inputs.<flake>.nixosModules.<module>` for external modules.
- Use `self` for internal references.

## Common Tasks

**Adding a new Host:**

1. Create `modules/hosts/<hostname>/default.nix`.
2. Define `flake.nixosConfigurations.<hostname>`.
3. Import `self.nixosModules.desktop` (or terminal/common).
4. Set `preferences.hostName` and hardware config.

**Adding a Package:**

1. If available in nixpkgs: add to `environment.systemPackages`.
2. If custom: add `modules/_pkgs/<name>.nix`, then add to system packages
   using `self.packages.${pkgs.stdenv.hostPlatform.system}.<name>`.

**Debugging Build Failures:**

1. Check `nix log` for detailed error messages.
2. Verify `path:.` is used (default in `rebuild.sh`) so dirty/ignored files
   are seen.
3. Check `impermanence` paths if state is lost on reboot.

## Wayland Clipboard (wl-copy)

**Critical:** When piping data to `wl-copy`, always specify `--type text/plain`
to prevent MIME type detection failures.

### The Problem

`wl-copy` auto-detects MIME types when reading from stdin. This detection
sometimes fails, resulting in garbage MIME types that applications cannot
paste with Ctrl+V (even though `wl-paste` works).

**Symptoms:**

- `wl-paste` returns correct content
- `wl-paste -l` shows garbage (e.g., `����U`) instead of `text/plain`
- Ctrl+V doesn't work in applications
- Content doesn't appear in cliphist

### The Fix

```bash
# BAD - MIME type may be detected incorrectly
echo "data" | wl-copy

# GOOD - Explicit MIME type
echo "data" | wl-copy --type text/plain
```

### In Nix Scripts

```nix
# BAD
printf '%s' "$VALUE" | wl-copy

# GOOD
printf '%s' "$VALUE" | wl-copy --type text/plain
```

### In TypeScript/Bun Scripts

```typescript
// Return the copy command with explicit type
return ["wl-copy", "--type", "text/plain"];
```

**Note:** Direct argument usage (`wl-copy "text"`) works fine - only piped
stdin has this issue.

## VPN SOCKS5 Proxy System

A modular SOCKS5 proxy system that routes traffic through OpenVPN
configurations with network namespace isolation and zero IP leak guarantee.

### VPN Proxy Architecture

```text
Application ───► SOCKS5 Proxy (localhost:10800)
                       │
                 ┌─────┴─────┐
                 │ Extract   │
                 │ Username  │
                 └─────┬─────┘
                       │
        ┌──────────────┼──────────────┐
        ▼              ▼              ▼
   "random"       "VPN Slug"      Invalid
   (or empty)     (exact match)   → notify
        │              │              │
        └──────────────┼──────────────┘
                       ▼
              Get/Create Namespace
                       │
    ┌──────────────────┼──────────────────┐
    ▼                  ▼                  ▼
┌─────────────┐  ┌─────────────┐  ┌─────────────┐
│ vpn-proxy-0 │  │ vpn-proxy-1 │  │ vpn-proxy-N │
│ OpenVPN     │  │ OpenVPN     │  │ OpenVPN     │
│ + kill-sw   │  │ + kill-sw   │  │ + kill-sw   │
└─────────────┘  └─────────────┘  └─────────────┘
```

### How It Works

1. **Single Port**: SOCKS5 proxy listens on `localhost:10800`
2. **Username = VPN**: The SOCKS5 username field specifies which VPN to use
3. **On-Demand**: VPNs start automatically on first request
4. **Auto-Cleanup**: Idle VPNs (5 min) are torn down completely

### VPN Proxy Components

| Package             | Location                    | Purpose                         |
| ------------------- | --------------------------- | ------------------------------- |
| `vpn-resolver`      | `bunjs/vpn-resolver.ts`     | VPN config parsing, caching     |
| `vpn-proxy`         | `bunjs/vpn-proxy.ts`        | SOCKS5 server with VPN routing  |
| `vpn-proxy-cleanup` | `bunjs/vpn-proxy-cleanup.ts`| Idle cleanup daemon             |
| `vpn-proxy-netns`   | `bunjs/vpn-proxy-netns.sh`  | Namespace setup with kill-switch|

### Usage

```bash
# Specific VPN via username
curl --proxy "socks5://AirVPN%20AT%20Vienna@127.0.0.1:10800" https://api.ipify.org

# Random VPN (any of these work)
curl --proxy "socks5://random@127.0.0.1:10800" https://api.ipify.org
curl --proxy "socks5://127.0.0.1:10800" https://api.ipify.org

# Check status (only CLI command available)
vpn-proxy status
```

### VPN Configuration

| Environment Variable       | Default         | Description                    |
| -------------------------- | --------------- | ------------------------------ |
| `VPN_DIR`                  | `~/Shared/VPNs` | Directory with `.ovpn` files   |
| `VPN_PROXY_PORT`           | `10800`         | Single listening port          |
| `VPN_PROXY_IDLE_TIMEOUT`   | `300`           | Seconds before idle cleanup    |
| `VPN_PROXY_RANDOM_ROTATION`| `300`           | Random VPN rotation interval   |

### Security Model

1. **Network Namespace Isolation**: Each VPN runs in isolated namespace with
   own network stack
2. **Kill-Switch**: nftables rules DROP all OUTPUT except `tun0` and VPN
   handshake
3. **DNS Isolation**: Per-namespace `/etc/netns/<name>/resolv.conf` prevents
   DNS leaks
4. **Zero IP Leak**: If VPN disconnects, all traffic is blocked (no fallback
   to host IP)

### Integration with qs-vpn

The `qs-vpn` script supports keybinds via the qs-dmenu framework:

- **Enter**: Connect to VPN via NetworkManager (existing behavior)
- **k**: Copy SOCKS5 proxy link (`socks5://VPN%20Name@127.0.0.1:10800`) to
  clipboard

The VPN activates automatically when the proxy link is first used - no manual
start needed.

### State Location

All runtime state is stored in `/dev/shm/vpn-proxy-$UID/`:

- `state.json`: Namespace tracking, last-used timestamps, random state
- `resolver-cache.json`: VPN config cache with mtime validation
- `openvpn-*.log`: Per-namespace OpenVPN logs

### Cleanup Behavior

- Proxies unused for 5 minutes are automatically torn down
- Namespace, veth pairs, iptables rules, and processes are fully cleaned
- Random VPN rotates every 5 minutes while in use
- Run `vpn-proxy stop-all` for emergency cleanup

## Quickshell Notification Center

A full-featured notification daemon and center implementing the Liquid Glass
design language, replacing swaync.

### Notification System Architecture

```text
┌─────────────────────────────────────────────────────────────┐
│                    NotificationServer                        │
│  (DBus org.freedesktop.Notifications)                       │
└─────────────────────┬───────────────────────────────────────┘
                      │
         ┌────────────┴────────────┐
         ▼                         ▼
┌─────────────────┐      ┌─────────────────────┐
│ NotificationPopup│      │  NotificationPanel  │
│ (Corner popups)  │      │  (Full sidebar)     │
└─────────────────┘      └─────────────────────┘
         │                         │
         └────────────┬────────────┘
                      ▼
              ┌───────────────┐
              │NotificationItem│
              │ (Glass UI)     │
              └───────────────┘
```

### Features

- **Popup Notifications**: Corner popups with auto-timeout (7s default)
- **Notification Panel**: Full sidebar with scrollable notification list
- **Actions Support**: Clickable action buttons from notification senders
- **App Icons**: Proper icon resolution using Quickshell.iconPath()
- **Copy Button**: Copy notification body to clipboard
- **Swipe to Dismiss**: Drag notifications left/right to dismiss
- **Expandable Body**: Long notifications can be expanded
- **Persistence**: Notifications survive restarts
  (stored in `~/.local/share/quickshell/`)
- **Do Not Disturb**: Suppress popup notifications
- **Ding Sounds**: Configurable per-urgency and per-app sound alerts

### CLI Commands

```bash
# Start the notification daemon (usually via autostart)
qs-notifications

# Toggle notification panel
qs-notifications toggle

# Show/hide panel explicitly
qs-notifications show
qs-notifications hide

# Get notification count
qs-notifications count
qs-notifications unread

# Clear all notifications
qs-notifications clear

# Do Not Disturb
qs-notifications dnd          # Get status
qs-notifications toggle-dnd   # Toggle DND

# Sound control
qs-notifications ding         # Play notification sound
qs-notifications set-volume 0.7  # Set volume (0.0-1.0)
```

### Sending Notifications with Ding Sound

The `qs-notify` command wraps `notify-send` with ding sound support:

```bash
# Basic notification
qs-notify "Title" "Body text"

# Notification with ding sound
qs-notify --ding "Alert" "Something happened"
qs-notify -d "Alert" "Something happened"

# With urgency and ding
qs-notify -u critical -d "Error" "Critical error occurred"

# Full options
qs-notify --ding --urgency critical --icon error --app MyApp "Title" "Body"
```

### Script Integration

For scripts that need to send notifications with ding sounds:

```bash
#!/usr/bin/env bash
# Option 1: Use qs-notify (recommended)
qs-notify --ding "Backup Complete" "All files synchronized"

# Option 2: Trigger ding separately
qs-notifications ding &
notify-send "Backup Complete" "All files synchronized"
```

### Ding Sound Settings

Configure via the settings panel (gear icon in notification center):

| Setting           | Default | Description                    |
| ----------------- | ------- | ------------------------------ |
| Volume            | 50%     | Sound volume (0-100%)          |
| Low Priority      | Off     | Play sound for low urgency     |
| Normal Priority   | On      | Play sound for normal urgency  |
| Critical Priority | On      | Play sound for critical urgency|

Per-app overrides can be set from the notification's context menu (⋮ button).

### Notification Configuration Files

| File                         | Location                       | Purpose                |
| ---------------------------- | ------------------------------ | ---------------------- |
| `notifications.json`         | `~/.local/share/quickshell/`   | Persisted notifications|
| `notification-settings.json` | `~/.local/share/quickshell/`   | Sound/DND settings     |

### Waybar Integration

The notification module in waybar shows unread count and toggles the panel:

```nix
"custom/notifications" = {
  format = "󰂚 {}";
  exec = "qs-notifications count";
  on-click = "qs-notifications toggle";
  interval = 1;
};
```

### Sound File

Default sound:
`/run/current-system/sw/share/sounds/freedesktop/stereo/message.oga`

To use a custom sound, modify `notification-center.qml` or set via environment
variable (future feature).
