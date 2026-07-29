---
title: KDE Plasma desktop
---

`modules/desktop/kde.nix` adds the KDE Plasma 6 stack used by both graphical hosts. Enable it per host with:

```nix
preferences.kde.enable = true;
```

## Runtime model

| Surface                | KDE module decision                                                                                                                      |
| ---------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| Session                | `services.desktopManager.plasma6.enable = true` plus `services.displayManager.plasma-login-manager.enable = true`.                       |
| Display manager safety | `services.displayManager.sddm.enable = lib.mkForce false`, so Plasma Login Manager and SDDM cannot both claim `display-manager.service`. |
| Polkit                 | KDE uses `polkit-kde-agent-1`, keeps `security.polkit.enable = true`, and narrows admin identities to the primary user.                  |
| GPG/SSH prompts        | `pinentry-qt` is forced for GnuPG and `ksshaskpass` is forced for SSH askpass.                                                           |
| Portals                | KDE portal is the preferred portal backend; GTK remains installed as fallback where upstream Plasma module includes it.                  |
| Shortcuts              | No Plasma shortcut declarations. Configure keybinds in KDE Settings. Important utility commands are installed directly on `PATH`.        |

## Impermanence boundary

KDE's configuration system is user-mutable by design. The module persists the files KDE edits instead of declaring those settings in Nix.

| Tier          | Examples                                                                                                                                                                                                                                                 | Notes                                                                        |
| ------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| Durable state | Selected `.config/*`, `.config/*.rc`, and `.local/share/*` paths | Shell layout, KWin, shortcuts, KWallet, places, and per-user Plasma choices. Each KConfig file is persisted explicitly so its atomic replacement remains an ordinary file rather than a fragile bind mount. |
| Cache         | `.cache/plasma-svgelements`, `.cache/plasmashell`, `.cache/qmlcache`, `.cache/thumbnails`, `wallpaper`                                                                                                                                                   | Rebuildable rendering/cache data and the local wallpaper selector cache.     |

KDE UserBase documents the cascading config-file model: defaults can come from system config trees, but `$KDEHOME` user config has highest precedence and apps rewrite these files. This module avoids lock-down entries, so System Settings remains the source of truth for user choices.

## Commands for Plasma shortcuts

Assign these in **System Settings → Keyboard → Shortcuts → Custom Shortcuts** as needed:

```text
kitty
librewolf
xdg-open https://x.com/i/grok
loginctl lock-session
qs-emoji
qs-nerd
qs-passmenu
qs-passmenu -a
qs-music-search
qs-music-local
qs-checklist
qs-vpn
toggle-lyrics-overlay
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

## Password menu

`qs-passmenu` reads the synchronized password store at
`~/.local/share/password-store`. The terminal profile exports this as an absolute
`PASSWORD_STORE_DIR` so KDE and other GUI launchers do not preserve `$HOME`
literally; the command also resolves that legacy literal form before searching.
The directory is persisted by
[`modules/common/impermanence.nix`](https://github.com/Vanadium5000/nixconf/blob/main/modules/common/impermanence.nix)
and synchronized by
[`modules/terminal/default.nix`](https://github.com/Vanadium5000/nixconf/blob/main/modules/terminal/default.nix).

VSCodium pins its Git executable to the system profile in
[`modules/desktop/vscodium/settings.json`](https://github.com/Vanadium5000/nixconf/blob/main/modules/desktop/vscodium/settings.json),
so source control does not depend on the desktop session's inherited `PATH`.

Both VSCodium and Antigravity expose that same `settings.json` through a regular
file bind mount at their `User/settings.json` paths. The source follows
`preferences.configFiles.source`: the checkout for local editing or the flake
store copy on hosts without a checkout. The checkout itself is a persistent bind
mount, so the source is available before either editor-file mount. Migration
removes the former symlink; a divergent legacy file is preserved beside the
mount point as `settings.json.pre-nixos-bind.<timestamp>`. The bind source is
never initialized from editor state, so the declarative setting remains
authoritative.

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
