---
title: Repository map
---

This flake is an operational NixOS fleet configuration, not a reusable framework.

```text
flake.nix
  -> lib/
  -> packages/
  -> external-packages/
  -> programmes/
  -> modules/
  -> hosts/*
  -> docs/
```

## Important local paths

- `AGENTS.md`: mandatory AI agent operating instructions at the repository root.
- `hosts/`: active host definitions.
- `packages/<name>/`: in-repo software with `package.nix` and any package-owned module/assets. The directory name is the exported package name; `bunjs-` is reserved for Bun-programme directories.
- `external-packages/<name>/`: packaged upstream projects with `package.nix`; `external-packages/update-pkgs/workflow.nix` owns package sets, updater modes, safe smoke arguments, custom-updater bindings, and documented manual coverage. Uncovered packages warn.
- `programmes/<name>/`: wrappers and configuration for upstream tools built with `BirdeeHub/nix-wrapper-modules`.
- `modules/terminal/`: terminal/server profile modules.
- `modules/terminal/docker/compose/<stack>/`: Docker Compose stack assets consumed by `modules/terminal/docker-compose-stacks.nix`.
- `modules/desktop/`: graphical profile modules for the KDE Plasma desktop stack.
- `modules/terminal/monitoring/homepage.nix`: Homepage dashboard cards and bookmarks.
- `lib/`: flat `*.nix` helper files.

Multi-command package owners export each runnable command directly. Do not add a convenience aggregate that pulls unrelated scripts, runtimes, browsers, or daemons into one closure; choose the exact `self.packages.<system>.<command>` at the consuming profile, service, host, or package. For example, music and credential commands depend on `qs-dmenu`, not the unrelated `qs-menus` aggregate.

Root architecture directories contain owner subdirectories only; do not add first-level implementation files there. `lib/` is the flat-helper exception. Keep first-level `docs/` entries as section directories containing `.md`/`.mdx` only; Docusaurus JS/TS code belongs in `packages/bunjs-docs/`.

## Repository audits

The flake exposes read-only audit commands from [`packages/repo-audits/package.nix`](https://github.com/Vanadium5000/nixconf/blob/main/packages/repo-audits/package.nix). They are intentionally opt-in: they do not add developer tooling to any host profile.

```bash
# Build or run from any Linux system with Nix; no global setup required.
nix run path:.#persist-audit
nix run path:.#nix-unused-audit

# Make unused Nix bindings fail the audit after reviewing the report.
nix run path:.#nix-unused-audit -- --strict
```

- `persist-audit` reports source locations of declared persistent and cache state.
- `nix-unused-audit` runs [deadnix](https://github.com/astro/deadnix) and [statix](https://github.com/oppiliappan/statix) over the root Nix architecture directories.
- `checks.repository-architecture` evaluates the first-level directory contract for `docs/`, `packages/`, `external-packages/`, and `programmes/`.
- `checks.update-pkgs-workflow-coverage` warns when an external package lacks an update mode in [`external-packages/update-pkgs/workflow.nix`](https://github.com/Vanadium5000/nixconf/blob/main/external-packages/update-pkgs/workflow.nix); `update-pkgs` emits the same warning interactively.
- `checks.installed-package-references` forces every host's `environment.systemPackages` derivation paths, catching stale auto-exported package attributes before a rebuild reaches `system-path` evaluation.

Run the checks directly without linking a `result` path:

```bash
nix build --no-link path:.#checks.x86_64-linux.repository-architecture
nix build --no-link path:.#checks.x86_64-linux.update-pkgs-workflow-coverage
nix build --no-link path:.#checks.x86_64-linux.installed-package-references
```

## Repository lint

[`rebuild.sh`](https://github.com/Vanadium5000/nixconf/blob/main/rebuild.sh) exposes a read-only `lint` action. It runs five independent lanes concurrently and emits every lane's full output before returning; a failure in one lane does not suppress the remaining diagnostics.

```bash
# Run the full repository check without requiring HOST or password-store access.
bun install --frozen-lockfile
./rebuild.sh --no-notify lint

# `validate` starts the same lint action alongside `nix flake check` by default.
HOST=legion5i ./rebuild.sh --debug --skip-secrets validate

# Evaluate only when lint is intentionally not part of this validation.
HOST=legion5i ./rebuild.sh --debug --skip-secrets --skip-lint validate
```

Bootstrap the pinned root Prettier and MarkdownLint CLI dependencies once per checkout with `bun install --frozen-lockfile`. The command then discovers tracked paths with `git ls-files`, so ignored dependency/build trees do not affect results. Its lanes are:

| Lane       | Files/tool                                                                                                                                    | Contract                                                                        |
| ---------- | --------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| LSP        | OpenCode diagnostics for `.nix`, `.sh`, `.bash`, and `.zsh`; eight bounded workers                                                            | LSP/server errors and error diagnostics fail; warnings remain visible           |
| Nix format | `nixfmt-tree -- --ci .`                                                                                                                       | Formatting must already match nixfmt                                            |
| TypeScript | Every tracked `.ts` through temporary, non-emitting `tsc` project configs                                                                     | Compiler diagnostics fail; `.tsx` is deliberately not part of the `.ts` request |
| Prettier   | Tracked formatter-managed JSON, CSS, TypeScript, and TSX sources                                                                              | Formatting must already match Prettier; `--cache` accelerates repeated runs     |
| Markdown   | Tracked `README.md` and `docs/` Markdown through [`.markdownlint.json`](https://github.com/Vanadium5000/nixconf/blob/main/.markdownlint.json) | Enabled MarkdownLint rules must pass                                            |

The TypeScript compiler comes from `nixpkgs#typescript`; temporary project configs type-check every tracked `.ts` file without emitting output. Root Bun workspaces install each package's declared dependencies once, and root `@types/bun` and `@types/node` provide the shared Bun/Node runtime declarations. The checkout and source files remain untouched. Prettier stores only its ignored cache state to accelerate repeated runs.

## Model catalog state

[`packages/models/`](https://github.com/Vanadium5000/nixconf/tree/main/packages/models) is the only checkout-owned location for `models.json`, model-group state, presets, provider choice, and local patches. `models sync` writes the catalog there; `models sync-config` derives the mutable OpenCode, OMO Slim, and OMP runtime files from the same state without fetching models. The command rejects the obsolete `modules/nixos/terminal/opencode/` state path, preventing divergent catalogs.

```bash
models sync          # Fetch and normalize the selected gateway catalog.
models sync-config   # Regenerate application configuration from local state.
```

Deleted checkout files should not create repo-local `.Trash-*` directories. `modules/common/impermanence.nix` enables trash support on persisted bind mounts and persists `~/.local/share/Trash` in `/persist/cache`, so VSCodium/Dolphin/GIO deletes route through the global XDG trash. `.Trash-*` is ignored only as a safety net, not as the intended state path.

## Change rule

When a change affects operator behavior, public routes, host services, or recovery steps, update `docs/` in the same patch.

## Host command help

[`packages/help/package.nix`](https://github.com/Vanadium5000/nixconf/blob/main/packages/help/package.nix)
exports a portable `help` command. Its companion
[`packages/help/module.nix`](https://github.com/Vanadium5000/nixconf/blob/main/packages/help/module.nix)
owns `preferences.commandHelp.commands`, generates `/etc/nixconf/help.json`, and
installs only command providers registered by enabled modules. Add an executable
where it is enabled, then add its record in the same conditional `config` block:

```nix
preferences.commandHelp.commands = [
  {
    command = "example-command";
    aliases = [ "ec" ]; # Optional.
    description = "One-line purpose shown by help.";
    usage = "example-command [options]";
    details = "Optional operational note.";
    package = examplePackage;
  }
];
```

`help` renders formatted records interactively, `help --plain` is pipe-safe, and
`help --pager` uses `less`. It reads `/etc/nixconf/help.json` by default, so the
index works even when a graphical or non-login shell did not inherit
`NIXCONF_HELP_DOCS`. `h` aliases `help`; terminal hosts also alias `rebuild` as
`r`. The package is testable off-host through `--docs FILE` or `--docs-json
JSON`.

## Manual `/persist/system` backups

`modules/terminal/btrbk.nix` installs nixpkgs `btrbk` plus a `btrbk-persist-system` wrapper on every terminal-profile host. It backs up the `/persist/system` Btrfs subvolume to a removable Btrfs target under:

```text
/run/media/<primary-user>/<external-drive-label>/BTRFS-BACKUPS/<host>-<persistent-8-hex-code>/
```

Defaults:

- Drive label preference: `preferences.btrbkPersistSystem.externalDriveLabel = "EXTERNAL DATA DRIVE"`.
- Generated config: `/etc/btrbk/persist-system.conf`.
- Persistent host suffix: `/var/lib/btrbk/persist-system-target-code`.
- Retention: `target_preserve_min 60d`, no automatic timer.
- Activation order: `createPersistentStorageDirs` before writing the host suffix, and the one-time random code generation runs under a subshell `umask 077` so activation does not leave root-only `/usr` (which breaks `#!/usr/bin/env` scripts like `./rebuild.sh` on impermanent roots).

Run manually only:

```bash
sudo btrbk-persist-system
sudo btrbk-persist-system --yes  # non-interactive root creation after safety checks
```

The wrapper verifies `/persist/system` is a Btrfs subvolume, confirms the configured drive path is the actual Btrfs mount point, prompts before first creating `BTRFS-BACKUPS`, creates the per-host target directory, and then calls `btrbk -c /etc/btrbk/persist-system.conf run`.

References: [btrbk README](https://digint.ch/btrbk/doc/readme.html), [btrbk.conf(5)](https://digint.ch/btrbk/doc/btrbk.conf.5.html), [btrbk(1)](https://digint.ch/btrbk/doc/btrbk.1.html).

## Graphical removable media

Graphical hosts use KDE Plasma/Solid with udisks2 for removable-disk tray actions, mount/unmount, and LUKS unlock prompts.

References: [freedesktop polkit architecture](https://www.freedesktop.org/software/polkit/docs/latest/polkit.8.html).

## KDE Plasma profile

`modules/desktop/kde.nix` enables Plasma 6 for hosts that set `preferences.kde.enable = true`. It uses Plasma Login Manager, KDE portal, KWallet, `polkit-kde-agent-1`, `pinentry-qt`, and `ksshaskpass`. It does not lock down Plasma settings in Nix; user-edited KDE config files and KWallet state are persisted through impermanence, while QML/theme/thumbnail caches stay cache-tier.

See [KDE Plasma desktop](./kde.md) for shortcut command names and the persistence boundary.

## Docs development dependencies

Run a single Bun workspace install from the repository root. The root lockfile pins dependencies declared by every custom package and provides the local dependencies for repository lint and editor diagnostics:

```bash
bun install --frozen-lockfile
```

Keep `packages/bunjs-docs/package-lock.json` committed: `packages/bunjs-docs/package.nix` uses it for reproducible `pkgs.buildNpmPackage` builds during rebuilds. The package stages root `docs/` beside the Docusaurus app with `NIXCONF_DOCS_ROOT=./docs`; packaged outputs still use Nix-managed dependency builds rather than checkout-local `node_modules`.

```nix
# Typical module shape in this repository.
{ self, ... }:
{
  flake.nixosModules.example = { config, lib, ... }: {
    options.services.example.enable = lib.mkEnableOption "example service";
    config = lib.mkIf config.services.example.enable {
      # service config
    };
  };
}
```

## References

- [NixOS module system](https://nixos.org/manual/nixos/stable/#sec-writing-modules)
- [flake-parts](https://flake.parts/)
- [import-tree](https://github.com/vic/import-tree)
