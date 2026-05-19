# ❄️ AGENTS.md — NixOS Flake Guidelines

> **CRITICAL: NEVER RUN REBUILD COMMANDS.** Do NOT execute `./rebuild.sh` or `nixos-rebuild`. The user performs all builds manually.

## 🛠️ Coding Standards

- **Modularisation**: One file per module. Use `import-tree`. Expose clean `options.preferences` instead of hardcoding.
- **Commenting**: Keep one dense comment near the setting: why, units/edge case, and source link/path. Preserve existing rationale; avoid prose blocks.
- **DRY**: Use `self.lib` for reusable functions and `config.preferences` for shared values.
- **Formatting**: Use `nixfmt-rfc-style` (2-space indent). Do NOT use alejandra.

## 🧊 Infrastructure Patterns

- **Impermanence**: Root is wiped on boot. Persist critical data (config, keys) in `impermanence.nixos.directories` and caches (llama.cpp, browser) in `.cache` paths.
- **Secrets**: Auto-injected by `rebuild.sh` from `pass` into `secrets.nix`. Access via `self.secrets.NAME`. Never commit `secrets.nix`.
- **Nix Evaluation**: Always use `path:.#` (not `.#`) to include untracked/dirty files.
- **Binary Caches**: Do not prioritize China-hosted or low-trust mirrors. Prefer official `cache.nixos.org` plus reputable CDN/project caches; put substituters and trusted public keys only in root `flake.nix` `nixConfig`, not host/module `nix.settings`; verify `.narinfo` hit/miss and one large NAR before changing priorities.
- **Wayland Clipboard**: Always use `wl-copy --type text/plain` when piping stdin.

## 🏠 Server Services (public server host)

- **Nginx Reverse Proxy**: All services are exposed via authenticated subdomains of the configured public base domain with Let's Encrypt (ACME).
- **CLIProxyAPI**: AI CLI wrapper (`services.cliproxyapi`). Port: 8317. Bound to localhost.
- **Dokploy**: Self-hosted deployment control plane (`services.dokploy`). Port: 3000. Bound to localhost behind nginx.
- **VPN Proxy**: SOCKS5/HTTP proxy with Web UI (`services.vpn-proxy`). Ports: 10800 (S5), 10801 (HTTP), 10802 (Web).

## 🖥️ Desktop Shell

- **DankMaterialShell** is the active desktop shell on graphical hosts (`preferences.dankMaterialShell.enable`). It replaces Waybar, Hyprlock, Hyprsunset, `qs-launcher`, and `qs-notifications` as primary shell surfaces.
- **DMS dependency note**: keep `programs.dank-material-shell.dgop.package = pkgs.unstable.dgop;` because the upstream DMS module expects the newer `dgop` package surface.
- **Quickshell scripts**: keep unrelated `qs-*` utilities such as `qs-dmenu`, `qs-passmenu`, `qs-wallpaper`, and overlays until they are explicitly migrated.

## 📋 Common Tasks

- **New Host**: Create `modules/hosts/<name>/default.nix`, define `flake.nixosConfigurations.<name>`, set `preferences.hostName`.
- **New Package**: From nixpkgs → `environment.systemPackages`. Custom → `modules/_pkgs/<name>.nix` (matches pname), access via `self.packages`.
- **Add Secret**:
  1. Add to `SECRETS_MAP` in `rebuild.sh`.
  2. `pass insert path/to/secret`.
  3. Secret becomes available as `self.secrets.VAR_NAME`.

## 🔄 Plan Submission

When a plan is ready, use `submit_plan`. Do NOT proceed until approved.
Once approved, use `TaskCreate` to track atomic steps. Mark `in_progress` before starting and `completed` immediately after verification.
