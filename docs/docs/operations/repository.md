---
title: Repository map
---

This flake is an operational NixOS fleet configuration, not a reusable framework.

```text
flake.nix
  -> modules/
  -> modules/hosts/*
  -> modules/nixos/*
  -> docs/
```

## Important local paths

- `AGENTS.md`: mandatory AI agent operating instructions at the repository root.
- `modules/hosts/`: active host definitions.
- `modules/nixos/terminal/`: terminal/server profile modules.
- `modules/nixos/desktop/`: graphical profile modules, including KDE Plasma and Hyprland/DMS stacks.
- `modules/nixos/terminal/monitoring/homepage.nix`: Homepage dashboard cards and bookmarks.

## Change rule

When a change affects operator behavior, public routes, host services, or recovery steps, update `docs/` in the same patch.

## Manual `/persist/system` backups

`modules/nixos/terminal/btrbk.nix` installs nixpkgs `btrbk` plus a `btrbk-persist-system` wrapper on every terminal-profile host. It backs up the `/persist/system` Btrfs subvolume to a removable Btrfs target under:

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

Graphical hosts use `modules/nixos/desktop/default.nix` to start `udiskie` as a `graphical-session.target` user service:

```text
udiskie --tray --appindicator --notify --no-automount --file-manager xdg-open
```

`udiskie` owns removable-disk tray actions, udisks2 mount/unmount, LUKS unlock prompts, and notifications. DankMaterialShell no longer owns USB management; `modules/nixos/desktop/dank-material-shell.nix` deletes the old `usbManager` plugin from persisted DMS config and removes its plugin settings on activation/restart.

References: [udiskie manual](https://github.com/coldfix/udiskie/blob/v2.6.2/doc/udiskie.8.txt), [freedesktop polkit architecture](https://www.freedesktop.org/software/polkit/docs/latest/polkit.8.html).

## KDE Plasma profile

`modules/nixos/desktop/kde.nix` enables Plasma 6 for hosts that set `preferences.kde.enable = true`. It uses Plasma Login Manager, KDE portal, KWallet, `polkit-kde-agent-1`, `pinentry-qt`, and `ksshaskpass`. It does not lock down Plasma settings in Nix; user-edited KDE config files and KWallet state are persisted through impermanence, while QML/theme/thumbnail caches stay cache-tier.

See [KDE Plasma desktop](./kde.md) for shortcut command names and the persistence boundary.

## Docs development dependencies

Run dependency installs from the repository root so Bun wires every local workspace, including this Docusaurus site and the Bun script workspace:

```bash
bun install
```

The root `package.json` includes `docs/` in `workspaces`, so that single command installs the Docusaurus packages needed by `docs/docusaurus.config.ts`, `docs/sidebars.ts`, and editor TypeScript language services. Keep `docs/package-lock.json` committed as well: the NixOS docs module at `modules/nixos/terminal/docs.nix` uses it for reproducible `pkgs.buildNpmPackage` builds during rebuilds.

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
