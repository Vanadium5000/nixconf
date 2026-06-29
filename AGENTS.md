# ❄️ AGENTS.md — NixOS Flake Guidelines

> **CRITICAL: NEVER RUN REBUILD COMMANDS except validation.** `HOST=<host> ./rebuild.sh validate` is allowed. Do not run rebuilding, switching, deploy, install, rollback, generation-changing commands, or `nixos-rebuild`; the user does those manually.
> **Sudo:** If a task requires live host inspection or root-owned state changes and passwordless sudo is unavailable, ask for the sudo password instead of stopping at a permissions error. Do not use sudo for rebuild/switch/deploy/install/rollback actions.

## 🛠️ Coding Standards

- **Modules**: one file per module; use `import-tree`; expose `options.preferences` instead of host hardcoding.
- **Comments**: one dense comment near the setting with why, units/edge case, and source link/path. Preserve rationale; avoid prose blocks.
- **DRY**: use `self.lib` for reusable functions and `config.preferences` for shared values.
- **Formatting**: from repo root run `nix run nixpkgs#nixfmt-tree -- .`; check-only with `nix run nixpkgs#nixfmt-tree -- --ci .`. Avoid file-by-file formatter drift.
- **README freshness**: update `README.md` in the same edit when changing flake inputs/exports, host inventory, profile/service architecture, public routes/ports, persistence or secrets flow, package exposure/update policy, script workspaces, or rebuild commands. Keep it factual and generated-from-current-code in spirit: expressive headings/tables/admonitions are fine.

## 🧊 Infrastructure Patterns

- **Impermanence**: root is wiped on boot. Persist critical state in `impermanence.nixos.directories`; caches go in `.cache` paths.
- **Secrets**: `rebuild.sh` fetches `pass` entries in parallel and atomically rewrites `secrets.nix`; consume as `self.secrets.NAME`; never commit `secrets.nix`. For script-only debugging use `HOST=<host> ./rebuild.sh --debug --skip-secrets validate` or `./rebuild.sh matrix` instead of rebuild actions.
- **Nix eval**: use `path:.#` rather than `.#` so untracked files are included.
- **Binary caches**: only configure substituters/trusted keys in root `flake.nix` `nixConfig`; verify `.narinfo` hit/miss and one large NAR before changing priorities.
- **Wayland clipboard**: pipe stdin with `wl-copy --type text/plain`.

## 🧭 Navigation / Live Topology — update when changed

Update this section in the same edit whenever host layout, routes, ports, primary services, desktop shell, persistence paths, or service module paths change.

```text
flake.nix -> import-tree [ ./modules ./secrets.nix ]; exports/options map: modules/exports.nix

main_vps: modules/hosts/main_vps/
├─ configuration.nix: imports terminal, cockpit, nix-dokploy, disko; enables Dokploy, CLIProxyAPI, Bifrost, OmniRoute, CPA Usage Keeper, VPN proxy, ntfy, homepage, mitmproxy
├─ remote-unlock.nix: systemd initrd network + SSH unlock on public :22 before stage-2 sshd starts
├─ my-website.nix: public edge; Traefik :80/:443 + ACME wildcard; services-auth-gateway 127.0.0.1:41276
│  ├─ Dokploy apps: apex/wildcard/openclaw -> dokploy-traefik 127.0.0.1:81
│  ├─ primary AI gateway: CLIProxyAPI 127.0.0.1:8317 -> https://cliproxyapi.<domain>; used by CPA Usage Keeper
│  ├─ Bifrost gateway/dashboard: 127.0.0.1:20129 -> https://bifrost.<domain>; proxies OpenAI-compatible requests to CLIProxyAPI
│  ├─ OmniRoute gateway/dashboard: 127.0.0.1:20128 -> https://omniroute.<domain>
│  └─ protected dashboards: dashboard/cockpit/mitmproxy/vpn/cpa-usage/portainer/mongo via services-auth; Baikal/DAV bypasses shared auth
└─ service settings/packages
   ├─ services.homepage-monitor: modules/nixos/terminal/monitoring/homepage.nix; local magic DNS names route enabled dashboard services from http://<name>/ to localhost ports while keeping direct localhost:<port> open
   ├─ services.omniroute: modules/nixos/terminal/omniroute.nix; modules/_pkgs/omniroute.nix
   ├─ services.bifrost: modules/nixos/terminal/bifrost.nix; upstream input github:maximhq/bifrost/transports/v1.5.15
   ├─ services.cliproxyapi: modules/nixos/terminal/cliproxyapi.nix; modules/_pkgs/cliproxyapi.nix
   ├─ services.cpa-usage-keeper: modules/nixos/terminal/cpa-usage-keeper.nix; modules/_pkgs/cpa-usage-keeper.nix
   ├─ services.services-auth-gateway: modules/nixos/terminal/services-auth-gateway.nix; modules/_pkgs/services-auth-gateway.nix
   ├─ services.vpn-proxy: modules/nixos/scripts/bunjs/proxy/service.nix; docs/scripts in modules/nixos/scripts/bunjs/proxy/
   └─ docker compose stacks: modules/nixos/terminal/docker-compose-stacks.nix discovers modules/docker/compose/<stack>/*.yaml; portainer enabled fleet-wide; gluetun-qbittorrent enabled on desktop hosts only

graphical hosts: modules/hosts/{legion5i,macbook}/
├─ desktop profile: modules/nixos/desktop/default.nix; terminal profile: modules/nixos/terminal/default.nix
├─ active shell: DankMaterialShell via preferences.dankMaterialShell.enable; module modules/nixos/desktop/dank-material-shell.nix
├─ DMS replaces Waybar, Hyprlock, Hyprsunset, qs-launcher, qs-notifications; keep dgop on pkgs.unstable.dgop
├─ keep unrelated qs-* tools (qs-dmenu/passmenu/wallpaper) until explicitly migrated
├─ Hyprland: modules/nixos/desktop/hyprland/ plus modules/user/hyprland.nix
├─ local VPN proxy enabled for desktop routing/testing
└─ qBittorrent WebUI: Gluetun/PIA stack binds 127.0.0.1:8088; qBittorrent shares Gluetun network namespace, pins torrent traffic to tun0, and downloads to persisted ~/Torrents

persistence helpers: modules/lib/_internal/persistence.nix; NixOS module modules/common/impermanence.nix; app state split across home persistence/cache for Orca, Limux, gh, OpenCode, OMP
monitoring dashboards: modules/nixos/terminal/monitoring/
```

## 📋 Common Tasks

- **New Host**: create `modules/hosts/<name>/default.nix`, define `flake.nixosConfigurations.<name>`, set `preferences.hostName`.
- **New Package**: nixpkgs package → `environment.systemPackages`; custom package → `modules/_pkgs/<name>.nix` matching `pname`, exposed via `self.packages`.
- **New Service Route**: add module/options, enable in `modules/hosts/main_vps/configuration.nix`, route in `modules/hosts/main_vps/my-website.nix`, then update Navigation / Live Topology above.
- **New Homepage Local Link**: add one entry to `localServices` in `modules/nixos/terminal/monitoring/homepage.nix` with `enable`, `port`, `label`, `icon`, and optional `path`. The module derives Homepage cards/bookmarks, `/etc/hosts` loopback names, and Traefik/nginx port-80 proxies from that single record. Use the magic URL `http://<name>/` on the dashboard; keep the underlying localhost port unchanged. Update README's magic DNS table and Navigation / Live Topology when the service set changes.
- **Add Secret**: add to `SECRETS_MAP` in `rebuild.sh`; `pass insert path/to/secret`; consume as `self.secrets.VAR_NAME`.
