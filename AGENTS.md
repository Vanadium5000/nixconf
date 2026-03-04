# AGENTS.md — NixOS Configuration Repository

> **NEVER RUN REBUILD COMMANDS. DO NOT EXECUTE `./rebuild.sh`,
> `nixos-rebuild`, OR ANY VARIANT. THE USER WILL REBUILD MANUALLY.**

## Coding Standards

### Modularisation

- **Single Responsibility**: Each module/file should do one thing well.
- **Composability**: Modules should be independently importable and composable.
- **Encapsulation**: Expose clean interfaces via `options`, not internals.
- **Directory Structure**: Group related functionality; use `import-tree`.

### Commenting

**PRESERVE ALL EXISTING COMMENTS. NEVER remove comments unless explicitly
asked.**

Comment the **WHY**, not the WHAT. Comment units/meanings, non-obvious values,
format explanations, rationale, edge cases, references, and module headers.
Do NOT write tautologies (`enable = true; # Enable the service`).

```nix
# BAD - tautology
virtualisation.docker.enable = true; # Enable docker
# GOOD - explains WHY
macAddress = "stable"; # "random" breaks captive portals on reconnect
# GOOD - explains unit/meaning
timeout = 3000; # 3s (reduced from 5s for faster fallback)
```

### DRY & Code Quality

- Use `self.lib` for reusable functions; `config.preferences` for shared values.
- If logic appears twice, extract it into a function or module.
- Use `mkMerge`/`mkIf` for conditional composition.
- Use `lib.types` for options (e.g., `types.port` not `types.int`).
- Use `lib.assertMsg` for eval-time validation.
- Prefer `inherit` for selective imports; import only what's needed.

## Formatting

Use `nixfmt-rfc-style`. **Do not use alejandra.** 2-space indentation.

```bash
nixfmt .              # Format all
nixfmt path/to/file.nix  # Format single file
```

## Module Structure

Modules follow the `flake-parts` pattern with `import-tree`:

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
        # Implementation
      };
    };
}
```

## Preferences System

Centralised options in `modules/common/base.nix`. Use these instead of
hardcoding values:

- `preferences.hostName` / `preferences.user.username` / `.extraGroups`
- `preferences.system.backlightDevice` / `preferences.allowedUnfree`
- `preferences.autostart` — list of packages/commands to autostart

**Always** use `config.preferences.user.username` instead of `"matrix"`.

## Custom Packages & Library

**Packages** (`modules/_pkgs/`): Auto-exposed via `self.packages`. File name
must match package name. No `default.nix` in `_pkgs/`.

**Library** (`modules/lib/`): Accessible via `self.lib`:

- `self.lib.persistence.mkPersistent` — persistent file/dir management
- `self.lib.generators.toHyprconf` — Nix attrs → Hyprland config

## Design System: Liquid Glass

Cyberpunk Electric Dark palette adapted from Apple's Liquid Glass (iOS 26).
Key tokens: Background `#000000`, Accent `#5454fc`, Active `#54fcfc`,
Glass `rgba(8,8,12,0.75)` + 8px blur, Font: JetBrainsMono Nerd Font.
Full spec: `modules/LIQUID_GLASS_SPEC.md`.

## Impermanence

Root is **ephemeral** (wiped on boot). You **MUST** persist anything that
should survive reboots.

```nix
# Critical data (backed up) — config, keys, state
impermanence.nixos.directories = [ "/var/lib/nixos" "/var/lib/bluetooth" ];
impermanence.home.directories = [ "Documents" ".ssh" ".config/obsidian" ];

# Cache (NOT backed up) — large/regenerable data (>50MB)
impermanence.nixos.cache.directories = [ "/var/cache/ollama" ];
impermanence.home.cache.directories = [ ".cache/mozilla" "Downloads" ];
```

Cache dirs persist across reboots but are excluded from backups.

## Self-References & Secrets

Access flake outputs via `self`:

- `self.nixosModules.*` / `self.packages.${pkgs.stdenv.hostPlatform.system}.*`
- `self.theme` / `self.colors` / `self.colorsNoHash` / `self.colorsRgba`
- `self.secrets.SECRET_NAME` — runtime secrets from `pass` via `secrets.nix`

### Secrets Management

Secrets are **auto-generated** by `rebuild.sh` from `pass` (password-store).
`secrets.nix` is gitignored and should never be edited manually.

**How it works**: `rebuild.sh` defines a `SECRETS_MAP` associative array
mapping environment variable names to `pass` paths. On rebuild, `load_secrets()`
reads each secret from `pass` and `write_secrets_nix()` generates `secrets.nix`
as `{ flake.secrets = { KEY = "value"; ... }; }`.

**To add a new secret**:

1. Add entry to `SECRETS_MAP` in `rebuild.sh`:
   `["MY_NEW_SECRET"]="path/in/pass"`
2. Create the `pass` entry: `pass insert path/in/pass`
3. Run `./rebuild.sh` — the secret becomes available as `self.secrets.MY_NEW_SECRET`

**Current secrets**: `PASSWORD_HASH`, `MY_WEBSITE_ENV`, `MONGODB_PASSWORD`,
`MONGO_EXPRESS_PASSWORD`, `ANTIGRAVITY_MANAGER_KEY`, `CLIPROXYAPI_KEY`,
`EXA_API_KEY`, `OPENCODE_SERVER_PASSWORD`.

**Input handling**: Use `inputs.nixpkgs.lib` for stdlib, `self` for internal.
Never commit secrets — `secrets.nix` is gitignored.

## Common Tasks

**New Host**: Create `modules/hosts/<name>/default.nix`, define
`flake.nixosConfigurations.<name>`, import `self.nixosModules.desktop`
(or `terminal`), set `preferences.hostName`.

**New Package**: From nixpkgs → `environment.systemPackages`. Custom →
`modules/_pkgs/<name>.nix`, reference via
`self.packages.${pkgs.stdenv.hostPlatform.system}.<name>`.

**Debug**: Check `nix log`, verify `path:.` usage, check `impermanence` paths.

## Nix Evaluation

**Always use `path:.#`** for flake references from the repo root, not `.#`.
The `path:.` prefix includes untracked/dirty files; `.#` only sees
git-tracked files and will fail on new modules.

```bash
# BAD — misses untracked files, fails on new modules
nix eval .#nixosConfigurations.ionos_vps.config.services.zeroclaw.enable

# GOOD — includes all files in working tree
nix eval path:.#nixosConfigurations.ionos_vps.config.services.zeroclaw.enable
```

## Wayland Clipboard

**Critical**: When piping to `wl-copy`, always use `--type text/plain`.
Auto-detection fails silently, breaking Ctrl+V paste and cliphist.

```bash
# BAD                              # GOOD
echo "x" | wl-copy                 echo "x" | wl-copy --type text/plain
```

```typescript
return ["wl-copy", "--type", "text/plain"]; // Always explicit type
```

Direct argument usage (`wl-copy "text"`) is fine — only piped stdin breaks.

## VPN SOCKS5 Proxy

SOCKS5 on `localhost:10800`, HTTP CONNECT on `localhost:10801`. Username field
selects VPN (e.g., `socks5://AirVPN%20AT%20Vienna@127.0.0.1:10800`). Empty
or `random` for random VPN. On-demand start, 5-min idle cleanup.

- **Scripts**: `modules/nixos/scripts/bunjs/proxy/` (BunJS/TypeScript)
- **State**: `/dev/shm/vpn-proxy-$UID/` (state.json, resolver-cache.json)
- **Security**: Network namespace isolation + nftables kill-switch per VPN
- **CLI**: `vpn-proxy status`, `vpn-proxy stop-all`

See `README.md` for full architecture, usage, and configuration.

## Notification Center

Custom Quickshell QML notification daemon (replaces swaync). Implements
`org.freedesktop.Notifications` DBus interface with Liquid Glass UI.

- **CLI**: `qs-notifications toggle|count|clear|toggle-dnd|ding|set-volume`
- **Send with ding**: `qs-notify --ding "Title" "Body"`
- **QML**: `modules/nixos/scripts/quickshell/notifications/`
- **State**: `~/.local/share/quickshell/` (notifications.json, settings)

See `README.md` for full features, CLI reference, and waybar integration.

## CUDA

Guard CUDA features behind `config.nixpkgs.config.cudaSupport`:

```nix
environment.variables = lib.mkIf (config.nixpkgs.config.cudaSupport or false) {
  USE_CUDA = "1";
  CUDA_PATH = "${pkgs.cudatoolkit}";
  LD_LIBRARY_PATH =
    "${pkgs.cudatoolkit}/lib:${pkgs.cudaPackages.cudnn}/lib"
    + (lib.optionalString (config.hardware ? nvidia)
        ":${config.hardware.nvidia.package}/lib") + ":$LD_LIBRARY_PATH";
};
```

## Server Services (ionos_vps only)

Three server services run exclusively on the `ionos_vps` host, enabled via
`services.<name>.enable = true` in the host config. All are disabled by default.

### ZeroClaw (`services.zeroclaw`)

Autonomous AI agent daemon running in sandboxed `zeroclaw daemon` mode.

- **Module**: `modules/nixos/terminal/zeroclaw.nix`
- **User**: Dedicated `zeroclaw` system user (isolated)
- **Data**: `/var/lib/zeroclaw/` (persisted via impermanence)
- **Config**: `/var/lib/zeroclaw/.zeroclaw/config.toml` (mutable, bootstrapped
  on first activation, never overwritten by Nix)
- **Workspace**: `/var/lib/zeroclaw/.zeroclaw/workspace/` (memory, skills, state)
- **Gateway**: `127.0.0.1:3100` (avoids port 3000 conflict with my-website)
- **Hardening**: `ProtectSystem=strict`, `ProtectHome=true`, own user/group

### OpenCode Server (`services.opencode-server`)

Headless OpenCode API server (`opencode serve`) for remote `opencode attach`.

- **Module**: `modules/nixos/terminal/opencode/server.nix` (extends `opencode` module)
- **Port**: `4096` (default, open in firewall, HTTP Basic auth via
  `OPENCODE_SERVER_PASSWORD`)
- **User**: Runs as `config.preferences.user.username` (needs hjem-deployed config)
- **Config**: Reads existing `~/.config/opencode/` deployed by the opencode module
- **Connect**: `opencode attach http://<host>:4096`

### CLIProxyAPI (`services.cliproxyapi`)

OpenAI-compatible API wrapping AI CLIs (Gemini, Claude, etc.).

- **Module**: `modules/nixos/terminal/cliproxyapi.nix`
- **User**: Dedicated `cliproxyapi` system user (isolated)
- **Data**: `/var/lib/cliproxyapi/` (persisted via impermanence)
- **Config**: `/var/lib/cliproxyapi/config.yaml` (mutable, hot-reloadable,
  bootstrapped on first activation)
- **Auth**: `/var/lib/cliproxyapi/auths/` (OAuth tokens for AI providers)
- **Port**: `8317` (default, open in firewall)
- **Initial setup**: OAuth requires one-time manual login per provider:
  `sudo -u cliproxyapi cliproxyapi -claude-login`
