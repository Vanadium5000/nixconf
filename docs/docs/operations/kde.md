---
title: KDE Plasma desktop
---

`modules/nixos/desktop/kde.nix` adds a KDE Plasma 6 stack beside the existing Hyprland/DankMaterialShell stack. `legion5i` enables it with:

```nix
preferences.kde.enable = true;
preferences.dankMaterialShell.enable = false;
```

## Runtime model

| Surface | KDE module decision |
| --- | --- |
| Session | `services.desktopManager.plasma6.enable = true` plus `services.displayManager.plasma-login-manager.enable = true`. |
| Display manager safety | `services.displayManager.sddm.enable = lib.mkForce false`, so Plasma Login Manager and SDDM cannot both claim `display-manager.service`. |
| Non-KDE stack isolation | Assertions reject KDE together with `home.programs.hyprland.enable` or `preferences.dankMaterialShell.enable`. Hyprland, hyprqt6engine, and tuigreet configs are gated off when KDE is active. |
| Polkit | KDE uses `polkit-kde-agent-1`, keeps `security.polkit.enable = true`, and narrows admin identities to the primary user. |
| GPG/SSH prompts | `pinentry-qt` is forced for GnuPG and `ksshaskpass` is forced for SSH askpass. |
| Portals | KDE portal is the preferred portal backend; GTK remains installed as fallback where upstream Plasma module includes it. |
| Shortcuts | No Plasma shortcut declarations. Configure keybinds in KDE Settings. Important utility commands are installed directly on `PATH`. |

## Impermanence boundary

KDE's configuration system is user-mutable by design. The module persists the files KDE edits instead of declaring those settings in Nix.

| Tier | Examples | Notes |
| --- | --- | --- |
| Durable state | `.config/kdeglobals`, `.config/kglobalshortcutsrc`, `.config/kwinrc`, `.config/kwinrulesrc`, `.config/plasma-org.kde.plasma.desktop-appletsrc`, `.config/plasmashellrc`, `.local/share/kwalletd`, `.local/share/plasma`, `.local/share/user-places.xbel` | Shell layout, KWin, shortcuts, KWallet, places, and per-user Plasma choices. |
| Cache | `.cache/plasma-svgelements`, `.cache/plasmashell`, `.cache/qmlcache`, `.cache/thumbnails`, `wallpaper` | Rebuildable rendering/cache data and the local wallpaper selector cache. |

KDE UserBase documents the cascading config-file model: defaults can come from system config trees, but `$KDEHOME` user config has highest precedence and apps rewrite these files. This module avoids lock-down entries, so System Settings remains the source of truth for user choices.

## Commands for Plasma shortcuts

Assign these in **System Settings → Keyboard → Shortcuts → Custom Shortcuts** as needed:

```text
kitty
librewolf
brave-origin
xdg-open https://x.com/i/grok
loginctl lock-session
qs-emoji
qs-nerd
qs-passmenu
qs-passmenu -a
qs-wallpaper
qs-music-search
qs-music-local
qs-checklist
qs-tools
qs-vpn
toggle-lyrics-overlay
toggle-pause-autoclickers
stop-autoclickers
voxtype record toggle
voxtype record cancel
sound-toggle
sound-up
sound-down
sound-up-small
sound-down-small
plasma-systemmonitor
```

Screenshots, screen recording, zoom, panels, window movement, and session power actions should use Plasma/KWin/Spectacle defaults unless a real gap appears.

## Validation

Safe validation command:

```bash
HOST=legion5i ./rebuild.sh --debug --skip-secrets validate
```

Do not run switch/rebuild/install/deploy/rollback actions from automation.

## References

- [NixOS KDE wiki](https://wiki.nixos.org/wiki/KDE)
- [KDE UserBase: configuration files](https://userbase.kde.org/KDE_System_Administration/Configuration_Files)
- [nixpkgs Plasma 6 module](https://github.com/NixOS/nixpkgs/blob/nixos-26.05/nixos/modules/services/desktop-managers/plasma6.nix)
- [nixpkgs Plasma Login Manager module](https://github.com/NixOS/nixpkgs/blob/nixos-26.05/nixos/modules/services/display-managers/plasma-login-manager.nix)
- [freedesktop polkit architecture](https://www.freedesktop.org/software/polkit/docs/latest/polkit.8.html)
