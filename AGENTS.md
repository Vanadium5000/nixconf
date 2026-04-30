# ❄️ AGENTS.md — NixOS Flake Guidelines

> **CRITICAL: NEVER RUN REBUILD COMMANDS.** Do NOT execute `./rebuild.sh` or `nixos-rebuild`. The user performs all builds manually.

## 🛠️ Coding Standards

- **Modularisation**: One file per module. Use `import-tree`. Expose clean `options.preferences` instead of hardcoding.
- **Commenting**: Explain **WHY**, not what. Document units (e.g. `timeout = 3000; # 3s`), rationale, and edge cases. Preserve existing comments.
- **DRY**: Use `self.lib` for reusable functions and `config.preferences` for shared values.
- **Formatting**: Use `nixfmt-rfc-style` (2-space indent). Do NOT use alejandra.

## 🧊 Infrastructure Patterns

- **Impermanence**: Root is wiped on boot. Persist critical data (config, keys) in `impermanence.nixos.directories` and caches (Ollama, browser) in `.cache` paths.
- **Secrets**: Auto-injected by `rebuild.sh` from `pass` into `secrets.nix`. Access via `self.secrets.NAME`. Never commit `secrets.nix`.
- **Nix Evaluation**: Always use `path:.#` (not `.#`) to include untracked/dirty files.
- **Wayland Clipboard**: Always use `wl-copy --type text/plain` when piping stdin.

## 🏠 Server Services (public server host)

- **Nginx Reverse Proxy**: All services are exposed via authenticated subdomains of the configured public base domain with Let's Encrypt (ACME).
- **CLIProxyAPI**: AI CLI wrapper (`services.cliproxyapi`). Port: 8317. Bound to localhost.
- **Dokploy**: Self-hosted deployment control plane (`services.dokploy`). Port: 3000. Bound to localhost behind nginx.
- **VPN Proxy**: SOCKS5/HTTP proxy with Web UI (`services.vpn-proxy`). Ports: 10800 (S5), 10801 (HTTP), 10802 (Web).

## 🎨 Liquid Glass Design System

Cyberpunk Electric Dark palette. Background: `#000000`, Accent: `#5454fc`, Active: `#54fcfc`. Glass: `rgba(8,8,12,0.75)` + 8px blur. Font: JetBrainsMono Nerd Font.

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
