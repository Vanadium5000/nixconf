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
- `packages/<name>/`: in-repo software with `package.nix` and any package-owned module/assets.
- `external-packages/<name>/`: packaged upstream projects with `package.nix`; `external-packages/update-pkgs/workflow.nix` owns automatic or documented-manual update workflow coverage and uncovered packages warn.
- `programmes/<name>/`: wrappers and configuration for upstream tools built with `BirdeeHub/nix-wrapper-modules`.
- `modules/terminal/`: terminal/server profile modules.
- `modules/terminal/docker/compose/<stack>/`: Docker Compose stack assets consumed by `modules/terminal/docker-compose-stacks.nix`.
- `modules/desktop/`: graphical profile modules for the KDE Plasma desktop stack.
- `modules/terminal/monitoring/homepage.nix`: Homepage dashboard cards and bookmarks.
- `lib/`: flat `*.nix` helper files.

Root architecture directories contain owner subdirectories only; do not add first-level implementation files there. `lib/` is the flat-helper exception. Keep first-level `docs/` entries as section directories containing `.md`/`.mdx` only; Docusaurus JS/TS code belongs in `packages/bunjs-docs/`.

Deleted checkout files should not create repo-local `.Trash-*` directories. `modules/common/impermanence.nix` enables trash support on persisted bind mounts and persists `~/.local/share/Trash` in `/persist/cache`, so VSCodium/Dolphin/GIO deletes route through the global XDG trash. `.Trash-*` is ignored only as a safety net, not as the intended state path.

## Change rule

When a change affects operator behavior, public routes, host services, or recovery steps, update `docs/` in the same patch.

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

Run dependency installs from the repository root only through package-scoped helper commands. The root manifest is glue; dependencies and lockfiles stay inside the package that uses them:

```bash
bun run install:all
```

Use `bun run install:docs`, `bun run install:scripts`, or `bun run install:lyrics` when working on one package. Keep `packages/bunjs-docs/package-lock.json` committed: the NixOS docs module at `packages/bunjs-docs/module.nix` uses it for reproducible `pkgs.buildNpmPackage` builds during rebuilds.

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
