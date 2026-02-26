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
