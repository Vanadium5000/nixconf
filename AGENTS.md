# ❄️ AGENTS.md — NixOS Flake Guidelines

> **CRITICAL: NEVER RUN REBUILD COMMANDS except validation.** `HOST=<host> ./rebuild.sh validate` is allowed. Do not run rebuilding, switching, deploy, install, rollback, generation-changing commands, or `nixos-rebuild`; the user does those manually.
> **Sudo:** If a task requires live host inspection or root-owned state changes and passwordless sudo is unavailable, ask for the sudo password instead of stopping at a permissions error. Do not use sudo for rebuild/switch/deploy/install/rollback actions.

## 🛠️ Coding Standards

- **Modules**: one file per module; use `import-tree`; expose `options.preferences` instead of host hardcoding.
- **Comments**: one dense comment near the setting with why, units/edge case, and source link/path. Preserve rationale; avoid prose blocks.
- **DRY**: use `self.lib` for reusable functions and `config.preferences` for shared values.
- **Formatting**: from repo root run `nix run nixpkgs#nixfmt-tree -- .`; check-only with `nix run nixpkgs#nixfmt-tree -- --ci .`. Avoid file-by-file formatter drift.
- **README & DOCS freshness**: update `README.md` & `docs/` in the same edit when changing flake inputs/exports, host inventory, profile/service architecture, public routes/ports, persistence or secrets flow, package exposure/update policy, script workspaces, or rebuild commands. Keep docs factual and generated-from-current-code in spirit. Include detailed fenced code blocks for commands/config, concrete explanations, diagrams when they clarify flow, source links to upstream docs/issues, and relative links to owning repo paths.
- **Architecture layout**: root architecture directories are subdirectory-owned; do not add first-level implementation files there. Exception: `lib/` is flat `*.nix` helpers. `packages/<name>/` owns in-repo software and must contain `package.nix`; its directory name is the exported package name, with `bunjs-` reserved for Bun-programme directories. Package scripts depend on the narrowest exported command, never an unrelated aggregate. `external-packages/<name>/` owns packaged upstream projects and must contain `package.nix`. `programmes/<name>/` owns wrappers/configuration for upstream tools and must contain `module.nix`, `package.nix`, or an owner-matching `<name>.nix` wrapper definition. **Wrapper-first package policy:** before packaging upstream software locally, check nixpkgs and flake inputs such as `llm-agents`; when it is already available, use `programmes/<name>/` with `nix-wrapper-modules` instead of repackaging it. Use `packages/` only for in-repo software and `external-packages/` only when upstream packaging is genuinely absent or needed. Keep `docs/` first-level entries as section directories containing only `.md`/`.mdx`; do not put JS/TS app code in `docs/`.
- **Repository audits**: keep `checks.repository-architecture` clean when changing root architecture trees. Use `nix run path:.#persist-audit` to locate persistence/cache declarations and `nix run path:.#nix-unused-audit` (or `-- --strict`) for Nix static analysis; these packages are opt-in and must not be installed by broad profiles.

## 🧊 Infrastructure Patterns

- **Impermanence**: root is wiped on boot. Persist critical state in `impermanence.nixos.directories`; caches go in `.cache` paths.
- **Secrets**: `rebuild.sh` fetches `pass` entries in parallel and atomically rewrites `secrets.nix`; consume as `self.secrets.NAME`; never commit `secrets.nix`. For script-only debugging use `HOST=<host> ./rebuild.sh --debug --skip-secrets validate` or `./rebuild.sh matrix` instead of rebuild actions.
- **Nix eval**: use `path:.#` rather than `.#` so untracked files are included.
- **Binary caches**: only configure substituters/trusted keys in root `flake.nix` `nixConfig`; verify `.narinfo` hit/miss and one large NAR before changing priorities.
- **Nixpkgs policy**: shared unfree/insecure allowances and temporary override expiry checks live in `lib/nixpkgs-policy.nix`; feature modules opt into policy entries with `self.lib.nixpkgs.allowedUnfreeFor`, not inline string lists.
- **Trash routing**: GUI deletes from persisted checkouts must use global XDG Trash. Keep `allowTrash = true` on persisted bind mounts in `modules/common/impermanence.nix` and persist `~/.local/share/Trash`; `.Trash-*` in the repo root is ignored only as a cleanup safety net.
- **Wayland clipboard**: pipe stdin with `wl-copy --type text/plain`.
- **OpenSnitch rules**: durable desktop firewall policy belongs in `services.opensnitch.mutableRules` in `modules/desktop/opensnitch.nix`; UI-created `/var/lib/opensnitch/rules` entries are temporary evidence to migrate or discard, because Nix resets rule JSON on activation/service start. Keep workflow details in `docs/operations/opensnitch.md`.

## 🧭 Navigation / Live Topology — update when changed

Update this section in the same edit whenever host layout, routes, ports, primary services, desktop shell, persistence paths, or service module paths change.

```text
flake.nix -> import-tree [ lib/default.nix, packages/_exports, selected package-owned modules/package modules, selected external service modules, programmes, modules, hosts, secrets.nix ]; exports/options map: modules/flake/exports.nix

main_vps: hosts/main_vps/
├─ configuration.nix: imports terminal, cockpit, nix-dokploy, disko; enables Dokploy, CLIProxyAPI, Bifrost, OmniRoute, CPA Usage Keeper, VPN proxy, ntfy, homepage, generated docs
├─ remote-unlock.nix: systemd initrd network + SSH unlock on public :22 before stage-2 sshd starts
├─ my-website.nix: public edge; Traefik :80/:443 + ACME wildcard; services-auth-gateway 127.0.0.1:41276
│  ├─ Dokploy apps: apex/wildcard/openclaw -> dokploy-traefik 127.0.0.1:81
│  ├─ primary AI gateway: CLIProxyAPI 127.0.0.1:8317 -> https://cliproxyapi.<domain>; used by CPA Usage Keeper
│  ├─ Bifrost gateway/dashboard: 127.0.0.1:20129 -> https://bifrost.<domain>; proxies OpenAI-compatible requests to CLIProxyAPI
│  ├─ OmniRoute gateway/dashboard: 127.0.0.1:20128 -> https://omniroute.<domain>
│  └─ protected dashboards: dashboard/docs/cockpit/vpn/cpa-usage/portainer/mongo via services-auth; Baikal/DAV bypasses shared auth
└─ service settings/packages
   ├─ services.homepage-monitor: modules/terminal/monitoring/homepage.nix; single serviceCatalog drives local/public cards (· :<port> badges), fleet bookmarks, Portainer/qBittorrent widgets, Nix Cyberpunk Electric Dark theme; magic DNS routes http://<name>/ → localhost ports with proxy headers/WebSockets/cookie/redirect handling
   ├─ services.nixconf-docs: packages/bunjs-docs/module.nix; builds docs/ with Docusaurus on rebuild and serves 127.0.0.1:8090
   ├─ services.omniroute: external-packages/omniroute/module.nix; external-packages/omniroute/package.nix
   ├─ services.bifrost: modules/terminal/bifrost.nix; upstream input github:maximhq/bifrost/transports/v1.5.15
   ├─ services.cliproxyapi: external-packages/cliproxyapi/module.nix; external-packages/cliproxyapi/package.nix
   ├─ services.cpa-usage-keeper: external-packages/cpa-usage-keeper/module.nix; external-packages/cpa-usage-keeper/package.nix
   ├─ services.services-auth-gateway: packages/services-auth-gateway/module.nix; packages/services-auth-gateway/package.nix
   ├─ services.vpn-proxy: packages/bunjs-vpn-proxy/module.nix; proxy docs/scripts in packages/bunjs-vpn-proxy/
   ├─ manual btrbk backups: modules/terminal/btrbk.nix; backs up /persist/system to /run/media/<user>/<drive>/BTRFS-BACKUPS/<host>-<persisted 8 hex>/ with no timer
   └─ docker compose stacks: modules/terminal/docker-compose-stacks.nix discovers modules/terminal/docker/compose/<stack>/*.yaml; portainer enabled fleet-wide; gluetun-qbittorrent enabled on desktop hosts only

graphical hosts: hosts/{legion5i,macbook}/
├─ desktop profile: modules/desktop/default.nix; terminal profile: modules/terminal/default.nix
├─ legion5i active shell: KDE Plasma 6 via preferences.kde.enable; module modules/desktop/kde.nix; Plasma Login Manager, KDE portal, KWallet, polkit-kde-agent-1, pinentry-qt/ksshaskpass; Plasma config stays imperative and persisted through impermanence
├─ macbook active shell: KDE Plasma 6 via preferences.kde.enable; module modules/desktop/kde.nix; Plasma Login Manager, KDE portal, KWallet, polkit-kde-agent-1, pinentry-qt/ksshaskpass; Plasma config stays imperative and persisted through impermanence
├─ keep unrelated qs-* tools (qs-dmenu/passmenu/VPN/checklist/lyrics) on KDE hosts; KDE installs important commands directly for imperative Plasma shortcuts rather than wrapping them
├─ removable media: KDE uses Plasma/Solid/udisks2 integration
├─ local VPN proxy enabled for desktop routing/testing
├─ OpenSnitch enabled with eBPF/nftables; advanced typed mutableRules reset /var/lib/opensnitch/rules from Nix every activation/service start while UI config persists in ~/.config/opensnitch; authenticated bypass wrapper is opensnitch-bypass
└─ qBittorrent WebUI: Gluetun/PIA stack binds 127.0.0.1:8088; qBittorrent shares Gluetun network namespace, pins torrent traffic to tun0, and downloads to persisted ~/Torrents

user-path bind helper: lib/bind-mounts.nix; NixOS impermanence module: modules/common/impermanence.nix; app state split across home persistence/cache for gh, OpenCode, OMP, Plasma, Firefox, VSCodium, and app data; btrbk host target suffix/transactions persist in /var/lib/btrbk
DNS stack (all hosts via modules/common/networking.nix): NSS prefers systemd-resolved (Cloudflare DoT opportunistic + DHCP/VPN link DNS + FallbackDNS); /etc/resolv.conf is static public 1.1.1.1/1.0.0.1/9.9.9.9/8.8.8.8 fail-open (not 127.0.0.53 stub); emergency tool dns-emergency (plain/dhcp/stop-resolved/restore) — docs/operations/dns.md
monitoring dashboards: modules/terminal/monitoring/
```

## 📋 Common Tasks

- **New Host**: create `hosts/<name>/configuration.nix`, define `flake.nixosConfigurations.<name>`, set `preferences.hostName`.
- **New Package**: check nixpkgs, then flake inputs such as `llm-agents`, before creating a local derivation. Use nixpkgs through `environment.systemPackages`; wrap an available upstream/input package in `programmes/<name>/<name>.nix` with `nix-wrapper-modules` (the wrapper exports a package but does not install it until a consumer selects it); use `packages/<name>/package.nix` only for in-repo software; use `external-packages/<name>/package.nix` only when upstream packaging is genuinely absent or needed. Package derivations match `pname` and are exposed via `self.packages`. Only actual `external-packages/` entries need `external-packages/update-pkgs/workflow.nix` coverage with an updater mode or documented manual reason; otherwise the coverage check and `update-pkgs` warn.
- **New Service Route**: add module/options, enable in `hosts/main_vps/configuration.nix`, route in `hosts/main_vps/my-website.nix`, then update Navigation / Live Topology above.
- **New Homepage Local Link**: add one entry to `localServices` in `modules/terminal/monitoring/homepage.nix` with `enable`, `port`, `label`, `icon`, and optional `path`. The module derives Homepage cards/bookmarks, `/etc/hosts` loopback names, and Traefik/nginx port-80 proxies from that single record. Use the magic URL `http://<name>/` on the dashboard; keep the underlying localhost port unchanged. Update README's magic DNS table and Navigation / Live Topology when the service set changes.
- **Docs Update**: edit `docs/**` for operator-facing changes. Keep first-level `docs/` entries as section directories with `.md`/`.mdx` only; JS/TS Docusaurus app code belongs in `packages/bunjs-docs/`. Prefer clear headings, tables, admonitions, Mermaid diagrams for topology/flow, and fenced blocks for Nix/shell/config examples. Every page that explains behavior should link the owning repo files with relative paths and cite external upstream references where behavior comes from.
- **Add Secret**: add to `SECRETS_MAP` in `rebuild.sh`; `pass insert path/to/secret`; consume as `self.secrets.VAR_NAME`.
