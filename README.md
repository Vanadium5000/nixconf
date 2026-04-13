# ❄️ nixconf

> **NixOS configuration flake with Liquid Glass design, ephemeral root, and
> modular architecture.**

A fully declarative, reproducible NixOS system built with `flake-parts` and
`import-tree`. Features an ephemeral root filesystem (impermanence), a custom
Quickshell-based desktop shell, SOCKS5/HTTP VPN proxy with zero-leak
kill-switch, and a Cyberpunk Electric Dark theme inspired by Apple's Liquid
Glass design language.

---

## 🎬 Demo

<!-- TODO: Add desktop overview video/demo -->

---

## 📸 Screenshots

<!-- TODO: Add screenshot of desktop with Hyprland + Waybar -->

<!-- TODO: Add screenshot of notification center (Liquid Glass) -->

<!-- TODO: Add screenshot of qs-launcher application launcher -->

<!-- TODO: Add screenshot of qs-dmenu with grid view -->

---

## 🖥️ Desktop Stack

| Component       | Tool                               | Notes                                         |
| --------------- | ---------------------------------- | --------------------------------------------- |
| Compositor      | **Hyprland** (Wayland)             | UWSM integration, dwindle layout              |
| Status Bar      | **Waybar**                         | 9 module categories, theme-aware              |
| Notifications   | **Quickshell Notification Center** | Custom-built, replaces swaync                 |
| Launcher        | **qs-launcher**                    | Quickshell QML, app + calculator mode         |
| Menu            | **qs-dmenu**                       | Fuzzy/prefix/exact, grid view, keybinds       |
| Terminal        | **Kitty**                          | Cursor trail, remote control                  |
| Shell           | **Zsh** + **Starship**             | fzf-tab, autosuggestions, syntax highlighting |
| Editor          | **Neovim** (NVF)                   | Primary `$EDITOR`, custom NVF config          |
| IDE             | **VSCodium** / **Antigravity**     | Declarative extensions, custom theme          |
| AI Coding       | **OpenCode**                       | Terminal AI assistant with MCP servers        |
| AI Assistant    | **OpenClaw**                       | AI gateway                                    |
| Browser         | **Librewolf**                      | uBlock Origin, Vimium, custom user.js         |
| File Manager    | **Dolphin** (KDE)                  | kio-extras, kio-admin                         |
| Display Manager | **tuigreet** (greetd)              | TUI greeter                                   |
| Lock Screen     | **Hyprlock**                       | Auto-lock via Hypridle (120s)                 |
| Wallpaper       | **Hyprpaper** + **qs-wallpaper**   | Grid preview selector                         |
| Blue Light      | **Hyprsunset**                     | Time-based profiles (6000K→1000K)             |
| Music           | **MPD** + **mpc**                  | PipeWire output, synced lyrics overlay        |
| Clipboard       | **cliphist** + **wl-clipboard**    | History via `SUPER+Z`                         |

---

## ✨ Features

### 🧊 Impermanence (Ephemeral Root)

The root filesystem is BTRFS and **wiped on every boot**. Only explicitly
persisted paths survive reboots. Two persistence tiers:

- **`/persist/system`** — Critical data (backed up): `/var/log`, machine-id,
  NetworkManager, bluetooth, SSH keys, Documents, password-store
- **`/persist/cache`** — Large/regenerable data (not backed up): browser cache,
  Steam, Downloads, Ollama models

Old root subvolumes are kept for 30 days before automatic cleanup.

### 🔒 VPN SOCKS5 Proxy System

A modular SOCKS5 + HTTP CONNECT proxy system that routes traffic through
OpenVPN with network namespace isolation and **zero IP leak guarantee**.

#### Architecture

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

#### How It Works

1. **Single Port**: SOCKS5 on `localhost:10800`, HTTP on `localhost:10801`
2. **Username = VPN**: The SOCKS5 username field specifies which VPN to use
3. **On-Demand**: VPNs start automatically on first request
4. **Auto-Cleanup**: Idle VPNs (5 min) are torn down completely

#### Usage

```bash
# Specific VPN via username
curl --proxy "socks5://AirVPN%20AT%20Vienna@127.0.0.1:10800" https://api.ipify.org

# Random VPN
curl --proxy "socks5://random@127.0.0.1:10800" https://api.ipify.org

# Check status
vpn-proxy status
```

#### Components

| Package             | Location                      | Purpose                          |
| ------------------- | ----------------------------- | -------------------------------- |
| `vpn-proxy`         | `bunjs/proxy/socks5-proxy.ts` | SOCKS5 server with VPN routing   |
| `http-proxy`        | `bunjs/proxy/http-proxy.ts`   | HTTP CONNECT proxy server        |
| `vpn-resolver`      | `bunjs/proxy/vpn-resolver.ts` | VPN config parsing, caching      |
| `vpn-proxy-cleanup` | `bunjs/proxy/cleanup.ts`      | Idle cleanup daemon              |
| `vpn-proxy-netns`   | `bunjs/proxy/netns.sh`        | Namespace setup with kill-switch |

#### Configuration

| Variable                    | Default         | Description                  |
| --------------------------- | --------------- | ---------------------------- |
| `VPN_DIR`                   | `~/Shared/VPNs` | Directory with `.ovpn` files |
| `VPN_PROXY_PORT`            | `10800`         | SOCKS5 listening port        |
| `VPN_PROXY_IDLE_TIMEOUT`    | `300`           | Seconds before idle cleanup  |
| `VPN_PROXY_RANDOM_ROTATION` | `300`           | Random VPN rotation interval |

#### 🛡️ Security Model

1. **Network Namespace Isolation** — Each VPN runs in isolated namespace
2. **Kill-Switch** — nftables rules DROP all OUTPUT except `tun0` + VPN
   handshake
3. **DNS Isolation** — Per-namespace `resolv.conf` prevents DNS leaks
4. **Zero IP Leak** — If VPN disconnects, all traffic is blocked (no fallback)

State stored in `/dev/shm/vpn-proxy-$UID/` (tmpfs, cleared on reboot).

### 🔔 Notification Center

A full-featured notification daemon and center implementing the Liquid Glass
design language, replacing swaync. Built with Quickshell QML.

#### Notification Architecture

```text
┌─────────────────────────────────────────────┐
│           NotificationServer                │
│  (DBus org.freedesktop.Notifications)       │
└──────────────────┬──────────────────────────┘
                   │
        ┌──────────┴──────────┐
        ▼                     ▼
  NotificationPopup    NotificationPanel
  (Corner popups)      (Full sidebar)
        │                     │
        └──────────┬──────────┘
                   ▼
           NotificationItem
           (Glass UI card)
```

#### Features

- 🔔 Popup notifications with auto-timeout (7s)
- 📜 Scrollable sidebar panel
- 🎯 Clickable action buttons
- 👆 Swipe to dismiss
- 📋 Copy notification body to clipboard
- 📖 Expandable long notifications
- 💾 Persistence across restarts
- 🔕 Do Not Disturb mode
- 🔊 Configurable per-urgency and per-app ding sounds

#### CLI Commands

```bash
qs-notifications toggle          # Toggle panel
qs-notifications count           # Get count
qs-notifications clear           # Clear all
qs-notifications toggle-dnd      # Toggle DND
qs-notifications ding            # Play sound
qs-notifications set-volume 0.7  # Set volume (0.0-1.0)
```

#### Sending Notifications with Ding

```bash
# Recommended: qs-notify wrapper
qs-notify --ding "Alert" "Something happened"
qs-notify -u critical -d "Error" "Critical error occurred"

# Or trigger ding separately
qs-notifications ding & notify-send "Title" "Body"
```

#### Ding Sound Settings

| Setting           | Default | Description                     |
| ----------------- | ------- | ------------------------------- |
| Volume            | 50%     | Sound volume (0-100%)           |
| Low Priority      | Off     | Play sound for low urgency      |
| Normal Priority   | On      | Play sound for normal urgency   |
| Critical Priority | On      | Play sound for critical urgency |

Per-app overrides available from the notification context menu (⋮ button).

#### Waybar Integration

```nix
"custom/notifications" = {
  format = "󰂚 {}";
  exec = "qs-notifications count";
  on-click = "qs-notifications toggle";
  interval = 1;
};
```

### 🎨 Liquid Glass Design System

Adapted from Apple's iOS 26 / macOS Tahoe design language for a **Cyberpunk
Electric Dark** palette.

| Token          | Value                   | Usage                      |
| -------------- | ----------------------- | -------------------------- |
| Background     | `#000000`               | Main background            |
| Alt Background | `#141420`               | Elevated surfaces          |
| Accent         | `#5454fc`               | Primary accent (blue)      |
| Active         | `#54fcfc`               | Active/hover accent (cyan) |
| Glass          | `rgba(8,8,12,0.75)`     | Glass surface fill         |
| Glass Blur     | `8px`                   | Backdrop blur radius       |
| Corner Radius  | `22px` / `12px`         | Large / small components   |
| Font           | JetBrainsMono Nerd Font | Monospace everywhere       |

Full specification: [`modules/LIQUID_GLASS_SPEC.md`](modules/LIQUID_GLASS_SPEC.md)

### 🔐 Secrets Management

Secrets flow through `pass` (password-store) → `secrets.nix` → `self.secrets`:

1. `rebuild.sh` reads secrets from `pass` based on `SECRETS_MAP`
2. Generates `secrets.nix` (gitignored)
3. `flake.nix` imports and exposes as `self.secrets`
4. Modules access via `self.secrets.SECRET_NAME`

### 🤖 AI & Machine Learning

| Tool                       | Purpose                      | Acceleration    |
| -------------------------- | ---------------------------- | --------------- |
| **Ollama**                 | Local LLM inference          | CUDA (legion5i) |
| **OpenClaw**               | AI assistant gateway         | —               |
| **PersonaLive**            | Real-time portrait animation | CUDA            |
| **whisper-cpp**            | Speech-to-text dictation     | CPU/CUDA        |
| **OpenCode**               | AI coding assistant          | —               |
| **sora-watermark-cleaner** | AI video watermark removal   | CUDA            |

### 💰 Cryptocurrency Wallets

All wallets use `pass` for password management and VPN proxy for privacy:

| Currency | Tool           | Script             |
| -------- | -------------- | ------------------ |
| Monero   | monero-cli     | `monero-wallet`    |
| Bitcoin  | Electrum       | `bitcoin-wallet`   |
| Litecoin | Electrum-LTC   | `litecoin-wallet`  |
| Ethereum | Foundry (cast) | `ethereum-wallet`  |
| Dogecoin | dogecoin-cli   | — (custom package) |

### 🛡️ Security & Pentesting Toolkit

| Category            | Tools                                                    |
| ------------------- | -------------------------------------------------------- |
| WiFi                | aircrack-ng, hostapd, linux-wifi-hotspot                 |
| Network             | nmap, bettercap, responder, snitch, termshark, mitmproxy |
| Web                 | gobuster, ffuf, wpscan, ZAP, sqlmap                      |
| Password            | hashcat, john, thc-hydra                                 |
| Reverse Engineering | ghidra, radare2, binwalk                                 |
| Utilities           | rustscan, socat, proxychains-ng, hcxtools                |

### 📊 System Monitoring & Dashboards

A fully declarative, ephemeral-root compatible monitoring stack.

| Service       | Port    | Description                                                                                                                                                 |
| ------------- | ------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Homepage**  | `8082`  | Central fleet dashboard portal linking all nodes and services. (ionos_vps only)                                                                             |
| **Netdata**   | `19999` | Real-time system monitoring (CPU, RAM, Disk, Containers). Runs in RAM mode on laptops to save disk/battery, and dbengine on servers for historical metrics. |
| **mitmproxy** | `8083`  | On-demand HTTPS traffic analysis proxy. See details below.                                                                                                  |

#### 🔍 mitmproxy (HTTPS Traffic Analysis)

A custom NixOS service module (`services.mitmproxy`) for on-demand packet inspection.

**Interception Modes:**

- `explicit`: Set `HTTPS_PROXY=http://127.0.0.1:8080` per-app (safest)
- `transparent`: nftables redirects all port 80/443 traffic to the proxy
- `local`: eBPF hooks into the `connect()` syscall (experimental)

**CA Certificate Setup:**
To avoid certificate errors, the OS must trust the mitmproxy CA. The CA is pre-generated securely and stored in `password-store`, then injected into the system via `secrets.nix`.
Because it's injected securely during evaluation, you can immediately set `services.mitmproxy.trustCA = true;` without needing a two-step deploy!

Access the Web UI at `http://127.0.0.1:8083` (password: `nixos`).

### 🖥️ Virtualisation

| Platform   | Tools                                                                      |
| ---------- | -------------------------------------------------------------------------- |
| Containers | **Podman** (Docker-compatible) with compose, TUI, nvidia-container-toolkit |
| VMs        | **libvirtd** + **QEMU** + **virt-manager**                                 |
| Android    | **Waydroid** with nftables, waydroid-total-spoof, waydroid-script          |

### 🔊 Audio Stack

- **PipeWire** + **WirePlumber** (ALSA + PulseAudio compat, 32-bit support)
- **MPD** for music playback with PipeWire output
- **playerctld** for MPRIS session control
- **Synced lyrics overlay** via Quickshell QML
- **EasyEffects** via Flatpak for audio processing

### 📁 File Synchronisation

| Method        | Purpose                                      | Transport |
| ------------- | -------------------------------------------- | --------- |
| **Unison**    | Bidirectional `~/Shared/` sync between hosts | Tailscale |
| **git-sync**  | Password-store auto-sync every 5 min         | Git/SSH   |
| **Syncthing** | General file sync (secondary)                | P2P       |

### 🌐 Encrypted DNS

- **dnscrypt-proxy** on `127.0.0.1:54` with DoH + DNSCrypt
- Cloudflare + Quad9 as preferred resolvers
- **systemd-resolved** with global routing (`~.`)
- MAC address randomisation, hostname suppression
- NetworkManager dispatcher forces `ignore-auto-dns`

---

## 🏠 Hosts

| Host          | Type            | Hardware               | User     | Key Features                                            |
| ------------- | --------------- | ---------------------- | -------- | ------------------------------------------------------- |
| **legion5i**  | Desktop Laptop  | Intel + Nvidia (PRIME) | `matrix` | CUDA, fine-grained GPU power mgmt, primary machine      |
| **macbook**   | Desktop Laptop  | MacBook Air (T2)       | `matrix` | T2 firmware, suspend workarounds, fn/ctrl swap          |
| **ionos_vps** | Headless Server | IONOS VPS              | `main`   | Personal website, AI gateway, reverse proxy, monitoring |

---

## 🛠️ Scripts & Tools

### Quickshell QML Scripts (`qs-*`)

| Script                  | Purpose                                 | Keybind       |
| ----------------------- | --------------------------------------- | ------------- |
| `qs-launcher`           | Application launcher + calculator       | `SUPER+SPACE` |
| `qs-dmenu`              | Universal fuzzy menu (rofi replacement) | —             |
| `qs-dock`               | Desktop dock panel                      | `SUPER+D`     |
| `qs-notifications`      | Notification daemon & center            | —             |
| `qs-notify`             | Send notifications with ding sound      | —             |
| `qs-emoji`              | Emoji picker (emojilib)                 | —             |
| `qs-nerd`               | Nerd Font glyph picker                  | —             |
| `qs-powermenu`          | Lock/Logout/Suspend/Reboot/Shutdown     | —             |
| `qs-vpn`                | VPN selector + proxy link copy          | —             |
| `qs-keybinds`           | Keybind help overlay                    | —             |
| `qs-askpass`            | Password prompt (`SUDO_ASKPASS`)        | —             |
| `qs-wallpaper`          | Wallpaper picker with grid preview      | —             |
| `qs-tools`              | Utility menu (crosshair, autoclicker)   | —             |
| `qs-passmenu`           | Password store browser + autotype       | —             |
| `qs-checklist`          | Daily checklist/todo manager            | —             |
| `qs-music-search`       | YouTube music search + download         | —             |
| `qs-music-local`        | Local music library browser             | —             |
| `toggle-crosshair`      | On-screen crosshair overlay             | —             |
| `toggle-lyrics-overlay` | Synced lyrics floating overlay          | —             |

### BunJS/TypeScript Scripts

| Script              | Purpose                             |
| ------------------- | ----------------------------------- |
| `dictation`         | Voice dictation via whisper-cpp     |
| `btrfs-backup`      | BTRFS snapshot backup TUI           |
| `synced-lyrics`     | Fetch synced lyrics from lrclib.net |
| `pomodoro`          | Pomodoro timer with notifications   |
| `git-sync-debug`    | Debug git-sync authentication       |
| `vpn-proxy`         | SOCKS5 proxy server (port 10800)    |
| `http-proxy`        | HTTP CONNECT proxy (port 10801)     |
| `vpn-resolver`      | VPN config parsing + cache          |
| `vpn-proxy-cleanup` | Idle namespace cleanup daemon       |

Run `bun install` or `npm install` from the repository root to hydrate the Bun
workspace used by these scripts. The root workspace points at
`modules/nixos/scripts/bunjs/`, which keeps editor/LSP dependencies working on a
fresh clone without hunting for nested `node_modules`.

See [`modules/nixos/scripts/bunjs/README.md`](modules/nixos/scripts/bunjs/README.md)
for BunJS development details.

### MCP Servers (Model Context Protocol)

| Server                | Purpose                               |
| --------------------- | ------------------------------------- |
| `markdown-lint-mcp`   | Markdownlint integration for AI tools |
| `quickshell-docs-mcp` | Quickshell documentation lookup       |
| `qmllint-mcp`         | QML linting integration               |
| `daisyui-mcp`         | DaisyUI component docs                |
| `powerpoint-mcp`      | PowerPoint creation                   |

### General Scripts

| Script                                     | Purpose                                      |
| ------------------------------------------ | -------------------------------------------- |
| `sound-change` / `sound-up` / `sound-down` | Volume control via WirePlumber               |
| `sound-toggle`                             | Mute toggle                                  |
| `colorpicker`                              | Screen color picker with history             |
| `toggle-lid-inhibit`                       | Toggle suspend-on-lid-close                  |
| `monero-wallet`                            | Monero CLI with pass + VPN                   |
| `bitcoin-wallet`                           | Electrum with pass + VPN                     |
| `litecoin-wallet`                          | Electrum-LTC with pass + VPN                 |
| `ethereum-wallet`                          | Foundry cast with pass + VPN                 |
| `autoclicker-daemon`                       | Multi-point autoclicker                      |
| `run-flatpak-instance`                     | Isolated multi-instance Flatpak              |
| `opencode-models`                          | Host-installed OpenCode / OMA model switcher |
| `rebuild.sh`                               | NixOS rebuild wrapper with secrets           |

---

## 📦 Custom Packages

All packages in `modules/_pkgs/` are auto-exposed via `self.packages`:

| Package                    | Description                             |
| -------------------------- | --------------------------------------- |
| `antigravity-manager`      | Antigravity Tools manager (RPM wrapped) |
| `aptos-fonts`              | Microsoft Aptos font family             |
| `cliproxyapi`              | CLI Proxy API tool (Go)                 |
| `daisyui-mcp`              | DaisyUI MCP server (Python/fastmcp)     |
| `dogecoin`                 | Dogecoin wallet CLI                     |
| `iloader`                  | iOS device management (AppImage)        |
| `niri-screen-time`         | Screen time tracker (Go, Wayland)       |
| `personalive`              | Real-time portrait animation (CUDA)     |
| `pomodoro-for-waybar`      | Waybar pomodoro widget (Python)         |
| `powerpoint-mcp`           | PowerPoint MCP server (Python)          |
| `quickshell-docs-markdown` | Quickshell docs as Markdown (Rust)      |
| `sideloader`               | iOS app sideloading tool                |
| `snitch`                   | TUI network connection inspector        |
| `sora-watermark-cleaner`   | AI video watermark remover (CUDA)       |
| `update-pkgs`              | Auto-updater for `_pkgs/` (nix-update)  |
| `waydroid-script`          | Waydroid add-on installer helper        |
| `waydroid-total-spoof`     | Waydroid device identity spoofing       |

---

## 📂 Repository Structure

```text
nixconf/
├── flake.nix              # Main flake definition
├── rebuild.sh             # System rebuild script (wraps nixos-rebuild)
├── secrets.nix            # Auto-generated secrets (gitignored)
├── modules/
│   ├── common/            # Shared base modules (impermanence, networking, keymap)
│   ├── hosts/             # Per-machine configs (legion5i, macbook, ionos_vps)
│   ├── nixos/
│   │   ├── desktop/       # Desktop environment (Hyprland, audio, browser, etc.)
│   │   ├── terminal/      # Terminal tools (nix, opencode, git-sync)
│   │   └── scripts/       # All scripts (quickshell/, bunjs/, general.nix)
│   ├── programmes/        # Application configurations (waybar, kitty, zsh)
│   ├── hjem/              # User environment (hjem — home-manager alternative)
│   ├── wrappers/          # Executable wrappers (kitty, zsh, starship)
│   ├── lib/               # Custom library (self.lib — persistence, generators)
│   ├── _pkgs/             # Custom package definitions (self.packages)
│   ├── theme.nix          # Theme definitions (self.theme / self.colors)
│   ├── custom-packages.nix # Package auto-loader
│   ├── flake-parts.nix    # Flake-parts configuration & overlays
│   └── LIQUID_GLASS_SPEC.md # Full Liquid Glass design specification
```

## 🧱 Modular Host Composition

Hosts now declare both their identity and their intended role explicitly via
profile toggles plus feature/service toggles.

- `preferences.profiles.terminal.enable` - enables the terminal profile module
- `preferences.profiles.desktop.enable` - enables the desktop profile module
- `preferences.profiles.laptop.enable` - laptop-oriented defaults
- `preferences.profiles.server.enable` - server-oriented defaults
- `preferences.hardware.tlp.enable` - laptop power tuning module
- `preferences.obs.enable` - OBS Studio feature toggle
- `services.*.enable` - daemon-style modules such as `openclaw`,
  `cliproxyapi`, `opencode-server`, `vpn-proxy`, `netdata-monitor`,
  `homepage-monitor`, and `mitmproxy`

This keeps hosts thin: import the reusable modules you need, then switch
features and services on or off in one place. Profiles are still regular NixOS
modules; the profile flags now gate their config instead of self-enabling via
`mkDefault`.

## 🔌 Export Surface

The flake keeps the existing flat exports such as `self.nixosModules.desktop`
for compatibility, and now also publishes grouped exports under
`self.moduleSets`:

- `self.moduleSets.profiles`
- `self.moduleSets.features`
- `self.moduleSets.services`
- `self.moduleSets.hosts`

The grouped module exports are stable. The rebuild-time module matrix is being
reworked so it can be generated without recursive flake evaluation.

Current flake app exports are intentionally conservative:

- `nix run .#rebuild` - wrapper around `rebuild.sh`

Some tools such as `opencode-models` remain host-installed runtime commands for
now because they still depend on host-specific NixOS module state and checked-out
repo data rather than a fully generic per-system package interface.

## 🤝 Contributing

### Bun / TypeScript tooling

From the repository root:

```bash
bun install
```

or:

```bash
npm install
```

Useful root scripts:

```bash
bun run build:vpn-proxy-web
bun run typecheck:scripts
```

### Local `skills.sh` skill dependencies

Locally installed `skills.sh` skills only add the skill metadata under
`.agents/skills/`. If a skill expects a real binary such as `playwright-cli`,
you must also provide that runtime declaratively in this repo.

The Playwright CLI setup in this repo is the reference pattern:

1. Add a repo package in `modules/_pkgs/<name>.nix`.
   - Package the upstream tool with Nix instead of relying on mutable global
     `npm`, `pip`, or `cargo` installs.
   - If the tool needs NixOS-specific defaults, wrap the binary and export the
     required environment there.
2. Install that package from the relevant host/profile module.
   - Example: `modules/nixos/desktop/default.nix` adds
     `selfpkgs.playwright-cli` because the local Playwright skill needs a
     `playwright-cli` command on desktop hosts.
3. Keep runtime-only browser or shared-library settings close to the host
   module that actually needs them.
   - Example: `PLAYWRIGHT_BROWSERS_PATH` stays in the desktop module because it
     configures the browser bundle available to user sessions.

For browser automation skills specifically, NixOS usually needs both the CLI
package and store-managed browser wiring because upstream tools often assume an
FHS path like `/opt/google/chrome` that does not exist on NixOS. The custom
`modules/_pkgs/playwright-cli.nix` wrapper ships a default config that points
Playwright at the nixpkgs Chromium bundle instead.

Checklist for adding dependencies for another local skill:

1. Read `.agents/skills/<skill>/SKILL.md` and list every external command it
   shells out to.
2. Prefer an existing nixpkgs package; if none exists in your pinned channel,
   add a small package in `modules/_pkgs/`.
3. Install that package from the correct module/profile via
   `environment.systemPackages`.
4. Add wrapper env/config only when the upstream default breaks on NixOS.
   - Good examples: executable paths, browser bundle paths, or turning off
     unsupported auto-download behavior.
5. Verify with a direct command from the repo root before rebuilding your
   system, for example:

```bash
nix build --no-link path:.#playwright-cli
result_path=$(nix build --print-out-paths --no-link path:.#playwright-cli)
"$result_path/bin/playwright-cli" open https://duckduckgo.com
```

This keeps skill runtimes reproducible and avoids hidden per-machine state.

### Adding a new module

1. Add the module under `modules/` in the closest matching domain.
2. Expose a complete option surface with `mkOption` / `mkEnableOption`.
3. Gate behavior with `mkIf cfg.enable` where appropriate.
4. Prefer shared values from `config.preferences` and
   `config.preferences.paths` over hardcoded absolute paths.
5. Add the module to the grouped flake exports if it is intended for reuse.

### Adding a new host

1. Create `modules/hosts/<name>/configuration.nix` and related hardware/disko
   files.
2. Define `flake.nixosConfigurations.<name>` and `flake.nixosModules.<name>Host`.
3. Set `preferences.hostName` and explicit `preferences.profiles.*` toggles.
4. Enable or disable feature/service modules in the host file rather than
   editing shared profile modules.

### Module Hierarchy

```text
terminal (base for all hosts)
  ├── common (base, impermanence, networking, keymap)
  ├── nix (Lix package manager, nix-index, unfree policy)
  ├── dev (MongoDB, Ollama, Podman, libvirtd)
  ├── tailscale, unison, git-sync, opencode
  └── vpn-proxy-service

desktop (extends terminal — GUI hosts only)
  ├── hyprland (compositor + keybinds + idle/lock)
  ├── audio (PipeWire, MPD, playerctl)
  ├── firefox/librewolf, vscodium, flatpaks
  ├── tuigreet, hyprsunset, bluetooth, qt, syncthing
  └── all quickshell/bunjs scripts
```

---

## 🔨 Build Commands

Uses `path:.` to ensure gitignored files (like `secrets.nix`) are included.

```bash
# Build and switch (most common)
HOST=legion5i ./rebuild.sh switch

# Build without switching
HOST=macbook ./rebuild.sh build

# Dry-run to preview changes
HOST=legion5i ./rebuild.sh dry-run

# Validate flake before switching
HOST=legion5i ./rebuild.sh --validate switch

# Deploy to remote host
HOST=ionos_vps ./rebuild.sh deploy root@host

# Install on new machine (nixos-anywhere)
HOST=macbook ./rebuild.sh install root@192.168.1.100

# Rollback / Show generations
HOST=legion5i ./rebuild.sh rollback
HOST=legion5i ./rebuild.sh generations
```

---

## 📥 Flake Inputs

| Input                 | Source                           | Purpose                              |
| --------------------- | -------------------------------- | ------------------------------------ |
| `nixpkgs`             | `nixos-25.11`                    | Main package repository (stable)     |
| `nixpkgs-unstable`    | `nixos-unstable`                 | Bleeding-edge packages               |
| `nur`                 | nix-community/NUR                | Nix User Repository                  |
| `nixos-hardware`      | LukeChannings/nixos-hardware     | Hardware configs (T2, Intel, Nvidia) |
| `flake-parts`         | hercules-ci/flake-parts          | Modular flake composition            |
| `import-tree`         | vic/import-tree                  | Auto-import directory trees          |
| `impermanence`        | nix-community/impermanence       | Ephemeral root management            |
| `persist-retro`       | Geometer1729/persist-retro       | Retroactive persistence              |
| `disko`               | nix-community/disko              | Declarative disk partitioning        |
| `hjem`                | feel-co/hjem                     | User environment (home-manager alt)  |
| `wrappers`            | Lassulus/wrappers                | Executable wrapping utility          |
| `nix-index-database`  | Mic92/nix-index-database         | Pre-built nix-index DB               |
| `nix-flatpak`         | gmodena/nix-flatpak              | Declarative Flatpak management       |
| `nix4vscode`          | nix-community/nix4vscode         | Auto-updated VSCode extensions       |
| `nvf-neovim`          | Vanadium5000/nvf-neovim          | Custom Neovim config                 |
| `opencode`            | anomalyco/opencode               | AI coding assistant                  |
| `hyprqt6engine`       | hyprwm/hyprqt6engine             | Qt6 theming for Hyprland             |
| `nixos-artwork`       | nixos/nixos-artwork              | NixOS wallpapers                     |
| `nixy-wallpapers`     | anotherhadi/nixy-wallpapers      | Extra wallpaper collection           |
| `my-website-frontend` | Vanadium5000/my-website-frontend | Personal website frontend            |
| `my-website-backend`  | Vanadium5000/my-website-backend  | Personal website backend             |

---

## 🎨 Theme & Colors

### Base16 — Cyberpunk Electric Dark

| Token    | Hex       | Usage                    |
| -------- | --------- | ------------------------ |
| `base00` | `#000000` | Background               |
| `base01` | `#0d0d0d` | Lighter background       |
| `base02` | `#383838` | Selection                |
| `base03` | `#545454` | Comments                 |
| `base04` | `#7c7c7c` | Dark foreground          |
| `base05` | `#a8a8a8` | Default foreground       |
| `base06` | `#d4d4d4` | Light foreground         |
| `base07` | `#ffffff` | Bright white             |
| `base08` | `#fc5454` | 🔴 Red                   |
| `base09` | `#fc9c54` | 🟠 Orange                |
| `base0A` | `#fcfc54` | 🟡 Yellow                |
| `base0B` | `#54fc54` | 🟢 Green                 |
| `base0C` | `#54fcfc` | 🔵 Cyan (accent alt)     |
| `base0D` | `#5454fc` | 🟣 Blue (primary accent) |
| `base0E` | `#fc54fc` | 🟣 Magenta               |
| `base0F` | `#a85454` | 🟤 Brown                 |

### Liquid Glass UI

| Property         | Value                            |
| ---------------- | -------------------------------- |
| Glass Background | `rgba(15,15,23,0.78)`            |
| Glass Blur       | `40px`                           |
| Accent           | `#0A84FF` (iOS system blue dark) |
| Accent Alt       | `#64D2FF` (iOS cyan dark)        |
| Corner Radius    | `22px` (large) / `12px` (small)  |
| Animation Speed  | `150ms` (fast) / `250ms` (slow)  |
| Font             | JetBrainsMono Nerd Font, 11pt    |

---

## 📝 License

This project is licensed under the GNU General Public License v3.0 (GPL-3.0). See the [LICENCE](LICENCE) file for details.
