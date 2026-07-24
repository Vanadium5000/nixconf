{
  self,
  ...
}:
{
  flake.nixosModules.hyprland =
    {
      lib,
      pkgs,
      config,
      ...
    }:
    let
      inherit (lib) getExe;

      inherit (self) theme colorsNoHash;

      mod = "SUPER";
      shiftMod = "SUPER_SHIFT";
      altMod = "ALT";
      altSuperMod = "SUPER_ALT";
      shiftAltSuperMod = "SUPER_SHIFT_ALT";
      terminal = self.packages.${pkgs.stdenv.hostPlatform.system}.terminal;
      qsDmenu = self.packages.${pkgs.stdenv.hostPlatform.system}.qs-dmenu;
      systemSettings = config.preferences.system;
      user = config.preferences.user.username;
      homeDirectory = config.preferences.paths.homeDirectory;
      kdeEnabled = lib.attrByPath [ "preferences" "kde" "enable" ] false config;

      hyprDmsFragments = [
        "colors.conf"
        "outputs.conf"
        "layout.conf"
        "cursor.conf"
        "binds.conf"
        "windowrules.conf"
      ];

      closeConfirmWindowSeconds = 20;

      hyprScreenshot = pkgs.writeShellScriptBin "hypr-screenshot" ''
        #!${pkgs.bash}/bin/bash
        set -euo pipefail

        case "''${1:-}" in
          area)
            mkdir -p ~/Pictures/Screenshots
            exec ${getExe pkgs.grimblast} save area ~/Pictures/Screenshots/screenshot_$(${pkgs.coreutils}/bin/date +'%Y-%m-%d_%H-%M-%S').png
            ;;
          monitor)
            mkdir -p ~/Pictures/Screenshots
            exec ${getExe pkgs.grimblast} save output ~/Pictures/Screenshots/screenshot_$(${pkgs.coreutils}/bin/date +'%Y-%m-%d_%H-%M-%S').png
            ;;
          edit)
            ${getExe pkgs.grim} -g "$(${getExe pkgs.slurp} -d)" - | exec ${getExe pkgs.swappy} -f -
            ;;
          ocr)
            text="$(${getExe pkgs.grim} -g "$(${getExe pkgs.slurp} -d)" - | ${getExe pkgs.tesseract} - -)"
            printf '%s' "$text" | ${pkgs.wl-clipboard}/bin/wl-copy --type text/plain
            if [ ''${#text} -le 120 ]; then
              ${getExe pkgs.libnotify} "OCR Result" "$text"
            else
              ${getExe pkgs.libnotify} "OCR Result" "''${text:0:100}...''${text: -20}"
            fi
            ;;
          qr)
            text="$(${getExe pkgs.grim} -g "$(${getExe pkgs.slurp} -d)" - \
              | ${pkgs.zbar}/bin/zbarimg - \
              | ${pkgs.gnused}/bin/sed 's/^QR-Code:[[:space:]]*//')"
            printf '%s' "$text" | ${pkgs.wl-clipboard}/bin/wl-copy --type text/plain
            if [ ''${#text} -le 120 ]; then
              ${getExe pkgs.libnotify} "ZBAR SCAN Result" "$text"
            else
              ${getExe pkgs.libnotify} "ZBAR SCAN Result" "''${text:0:100}...''${text: -20}"
            fi
            ;;
          record)
            mkdir -p ~/Videos
            exec ${getExe pkgs.wf-recorder} -g "$(${getExe pkgs.slurp} -d)" -f ~/Videos/rec_$(${pkgs.coreutils}/bin/date +'%Y-%m-%d_%H-%M-%S').mp4
            ;;
          stop-record)
            exec ${pkgs.procps}/bin/pkill -SIGINT wf-recorder
            ;;
          *)
            printf 'Usage: hypr-screenshot {area|monitor|edit|ocr|qr|record|stop-record}\n' >&2
            exit 2
            ;;
        esac
      '';

      hyprScreenshotExe = getExe hyprScreenshot;

      hyprClipboard = pkgs.writeShellScriptBin "hypr-clipboard" ''
        #!${pkgs.bash}/bin/bash
        set -euo pipefail

        command="''${1:-history}"
        shift || true

        state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/hypr-tools"
        log_file="$state_dir/hypr-clipboard.log"
        mkdir -p "$state_dir"
        exec > >(tee -a "$log_file") 2>&1

        log() { printf '[%(%Y-%m-%dT%H:%M:%S%z)T] %s\n' -1 "$*"; }
        notify() { ${pkgs.libnotify}/bin/notify-send -a hypr-clipboard "$@" >/dev/null 2>&1 || true; }

        usage() {
          cat <<'EOF'
        Usage: hypr-clipboard [history|clear]

        history  Open clipboard history with image previews and restore the selected item
        clear    Clear cliphist history

        Logs: ~/.local/state/hypr-tools/hypr-clipboard.log
        EOF
        }

        mime_for_ext() {
          case "$1" in
            jpg|jpeg) printf 'image/jpeg' ;;
            png) printf 'image/png' ;;
            bmp) printf 'image/bmp' ;;
            gif) printf 'image/gif' ;;
            webp) printf 'image/webp' ;;
            *) printf 'application/octet-stream' ;;
          esac
        }

        case "$command" in
          history)
            tmp_dir="$(${pkgs.coreutils}/bin/mktemp -d -t cliphist-preview.XXXXXXXXXX)"
            cleanup() { rm -rf "$tmp_dir"; }
            trap cleanup EXIT

            menu_file="$tmp_dir/menu"
            ${pkgs.cliphist}/bin/cliphist list | while IFS= read -r entry; do
              id="''${entry%%$'\t'*}"
              preview="''${entry#*$'\t'}"
              if [[ "$preview" =~ binary.*(png|jpg|jpeg|bmp|gif|webp) ]]; then
                ext="''${BASH_REMATCH[1]}"
                icon_file="$tmp_dir/$id.$ext"
                ${pkgs.cliphist}/bin/cliphist decode <<<"$entry" >"$icon_file" 2>/dev/null || true
                printf '%s\0icon\x1f%s\n' "$entry" "$icon_file"
              else
                printf '%s\n' "$entry"
              fi
            done > "$menu_file"

            selection="$(env DMENU_ICON_SIZE=96 ${getExe qsDmenu} -p 'Clipboard' < "$menu_file")" || exit 0
            [ -n "$selection" ] || exit 0

            preview="''${selection#*$'\t'}"
            if [[ "$preview" =~ binary.*(png|jpg|jpeg|bmp|gif|webp) ]]; then
              ext="''${BASH_REMATCH[1]}"
              mime="$(mime_for_ext "$ext")"
              data_file="$tmp_dir/selection.$ext"
              ${pkgs.cliphist}/bin/cliphist decode <<<"$selection" >"$data_file"
              ${pkgs.wl-clipboard}/bin/wl-copy --type "$mime" < "$data_file"
              notify "Clipboard restored" "$mime image"
              log "restored image clipboard item as $mime"
            else
              ${pkgs.cliphist}/bin/cliphist decode <<<"$selection" | ${pkgs.wl-clipboard}/bin/wl-copy
              notify "Clipboard restored" "Text/item restored"
              log "restored non-image clipboard item"
            fi
            ;;
          clear)
            ${pkgs.cliphist}/bin/cliphist wipe
            notify "Clipboard history cleared" "cliphist database wiped"
            log "cleared cliphist history"
            ;;
          help|-h|--help)
            usage
            ;;
          *)
            usage >&2
            exit 2
            ;;
        esac
      '';

      hyprClipboardExe = getExe hyprClipboard;
      disableAirplaneModeKey = pkgs.writeShellScriptBin "disable-airplane-mode-key" ''
        #!${pkgs.bash}/bin/bash
        set -euo pipefail

        ${pkgs.networkmanager}/bin/nmcli radio all on >/dev/null 2>&1 || true
        ${pkgs.util-linux}/bin/rfkill unblock all >/dev/null 2>&1 || true
      '';
      disableAirplaneModeKeyExe = getExe disableAirplaneModeKey;

      closeActiveWindow = pkgs.writeShellScriptBin "hypr-close-active-window" ''
        #!${pkgs.bash}/bin/bash
        set -euo pipefail

        STATE_FILE="/dev/shm/hyprland-close-confirm-$UID"
        LOCK_FILE="$STATE_FILE.lock"
        CONFIRM_WINDOW_SECONDS=${toString closeConfirmWindowSeconds}
        NOW_SECONDS=''${EPOCHREALTIME%.*}

        # Serialize rapid presses so lag cannot interleave reads/writes and close the
        # wrong window while the confirmation state is being refreshed.
        exec 9>"$LOCK_FILE"
        ${pkgs.util-linux}/bin/flock -x 9

        if [ -r "$STATE_FILE" ]; then
          IFS=' ' read -r LAST_PRESS_SECONDS _ < "$STATE_FILE" || true

          if [ -n "''${LAST_PRESS_SECONDS:-}" ]; then
            if (( NOW_SECONDS - LAST_PRESS_SECONDS <= CONFIRM_WINDOW_SECONDS )); then
              rm -f "$STATE_FILE"
              exec ${pkgs.hyprland}/bin/hyprctl dispatch 'hl.dsp.window.close()'
            fi
          fi
        fi

        # Persist the first press in tmpfs so confirmation stays fast even when the
        # rest of the system is under I/O pressure, and stale state disappears on reboot.
        printf '%s\n' "$NOW_SECONDS" > "$STATE_FILE"

        # Fire-and-forget reminder so a sluggish notification stack never delays the
        # keybind itself or shortens the effective double-press window.
        (
          ${pkgs.libnotify}/bin/notify-send \
            -u low \
            -t 2000 \
            "Close window" \
            "Press SUPER+Q again within ''${CONFIRM_WINDOW_SECONDS}s to close this app."
        ) >/dev/null 2>&1 < /dev/null &
      '';
      closeActiveWindowScript = getExe closeActiveWindow;

      # ═══════════════════════════════════════════════════════════════════
      # UNIFIED KEYBIND DEFINITIONS - Single source of truth
      # Each keybind has: key (hyprland format), exec, description, category
      # ═══════════════════════════════════════════════════════════════════

      # Helper to create a keybind entry
      kb = key: exec: description: category: {
        inherit
          key
          exec
          description
          category
          ;
      };

      # All keybinds defined in one place
      keybinds = {
        # ── Apps ──
        apps = [
          (kb "${mod},RETURN" "exec, ${getExe terminal}" "Open terminal" "Apps")
          (kb "${mod},B" "exec, librewolf" "Open LibreWolf browser" "Apps")
          (kb "${shiftMod},B" "exec, brave-origin" "Open Brave Origin browser" "Apps")
          (kb "${mod},G" "exec, xdg-open https://x.com/i/grok" "Open Grok AI" "Apps")
          (kb "${mod},L" "exec, dms ipc call lock lock" "Lock screen" "Apps")
        ];

        # ── Windows ──
        windows = [
          (kb "${mod},Q" "exec, ${closeActiveWindowScript}" "Close active window (press twice)" "Windows")
          (kb "${altSuperMod},Q" "exec, hyprctl kill" "Force kill window (click)" "Windows")
          (kb "${shiftMod},F" "togglefloating," "Toggle floating mode" "Windows")
          (kb "${shiftMod},C" "centerwindow" "Center floating window" "Windows")
          (kb "${mod},F" "fullscreen" "Toggle fullscreen" "Windows")
          (kb "${shiftMod},G" "togglegroup" "Toggle tabbed window group" "Windows")
          (kb "${mod} CTRL, G" "moveintogroup, r" "Group with right window" "Windows")
          (kb "${mod} CTRL, backslash" "layoutmsg, preselect r" "Preselect next split right" "Windows")
          (kb "${shiftMod},backslash" "layoutmsg, swapsplit" "Swap split orientation" "Windows")
          (kb "${mod},Y" "pseudo" "Toggle pseudotile" "Windows")
          (kb "${shiftMod},Y" "layoutmsg, movetoroot" "Promote window to layout root" "Windows")
          (kb "${mod},left" "movefocus, l" "Focus window left" "Windows")
          (kb "${mod},right" "movefocus, r" "Focus window right" "Windows")
          (kb "${mod},up" "movefocus, u" "Focus window up" "Windows")
          (kb "${mod},down" "movefocus, d" "Focus window down" "Windows")
          (kb "${shiftMod},left" "movewindow, l" "Move window left" "Windows")
          (kb "${shiftMod},right" "movewindow, r" "Move window right" "Windows")
          (kb "${shiftMod},up" "movewindow, u" "Move window up" "Windows")
          (kb "${shiftMod},down" "movewindow, d" "Move window down" "Windows")
          (kb "${shiftMod} CTRL, left" "swapwindow, l" "Swap window left" "Windows")
          (kb "${shiftMod} CTRL, right" "swapwindow, r" "Swap window right" "Windows")
          (kb "${shiftMod} CTRL, up" "swapwindow, u" "Swap window up" "Windows")
          (kb "${shiftMod} CTRL, down" "swapwindow, d" "Swap window down" "Windows")
          (kb "${altSuperMod},left" "focusmonitor, l" "Focus left monitor" "Windows")
          (kb "${altSuperMod},right" "focusmonitor, r" "Focus right monitor" "Windows")
          (kb "${altSuperMod},up" "focusmonitor, u" "Focus upper monitor" "Windows")
          (kb "${altSuperMod},down" "focusmonitor, d" "Focus lower monitor" "Windows")
          (kb "${shiftAltSuperMod},left" "movewindow, mon:l" "Move window to left monitor" "Windows")
          (kb "${shiftAltSuperMod},right" "movewindow, mon:r" "Move window to right monitor" "Windows")
          (kb "${shiftAltSuperMod},up" "movewindow, mon:u" "Move window to upper monitor" "Windows")
          (kb "${shiftAltSuperMod},down" "movewindow, mon:d" "Move window to lower monitor" "Windows")
          (kb "${mod},backslash" "togglesplit," "Toggle window split direction" "Windows")
          (kb "${mod},TAB" "cyclenext," "Focus next window" "Windows")
          (kb "${mod},TAB" "bringactivetotop" "Raise focused floating window" "Windows")
          (kb "${shiftMod},TAB" "cyclenext, prev" "Focus previous window" "Windows")
          (kb "${shiftMod},TAB" "bringactivetotop" "Raise focused floating window" "Windows")
        ];

        # ── Resize (binde - repeat) ──
        resize = [
          (kb "${mod} CTRL, right" "resizeactive, 30 0" "Resize window right" "Windows")
          (kb "${mod} CTRL, left" "resizeactive, -30 0" "Resize window left" "Windows")
          (kb "${mod} CTRL, up" "resizeactive, 0 -30" "Resize window up" "Windows")
          (kb "${mod} CTRL, down" "resizeactive, 0 30" "Resize window down" "Windows")
        ];

        # ── Workspaces ──
        workspaces = [
          (kb "${mod},mouse_down" "workspace, e+1" "Next workspace" "Workspaces")
          (kb "${mod},mouse_up" "workspace, e-1" "Previous workspace" "Workspaces")
          (kb "${mod},A" "togglespecialworkspace, magic" "Toggle scratchpad" "Workspaces")
          (kb "${shiftMod},A" "movetoworkspace, special:magic" "Move window to scratchpad" "Workspaces")
        ];

        # ── Menus ──
        menus = [
          (kb "${mod},D" "exec, dms ipc call control-center toggle" "Toggle control center" "Menus")
          (kb "${shiftMod},D" "exec, dms ipc call dock toggle" "Toggle DMS dock" "Menus")
          (kb "${mod},SPACE" "exec, dms ipc call spotlight toggle" "App launcher" "Menus")
          (kb "${mod},E" "exec, ${
            getExe self.packages.${pkgs.stdenv.hostPlatform.system}.qs-emoji
          }" "Emoji picker" "Menus")
          (kb "${mod},N" "exec, ${
            getExe self.packages.${pkgs.stdenv.hostPlatform.system}.qs-nerd
          }" "Nerd font icons picker" "Menus")
          (kb "${mod},Z" "exec, ${hyprClipboardExe} history" "Clipboard history" "Menus")
          (kb "${mod},W" "exec, ${
            getExe self.packages.${pkgs.stdenv.hostPlatform.system}.qs-wallpaper
          }" "Wallpaper selector" "Menus")
          (kb "${mod},P" "exec, ${
            getExe self.packages.${pkgs.stdenv.hostPlatform.system}.qs-passmenu
          }" "Password manager" "Menus")
          (kb "${shiftMod},P" "exec, ${
            getExe self.packages.${pkgs.stdenv.hostPlatform.system}.qs-passmenu
          } -a" "Password manager (autotype)" "Menus")
          (kb "${mod},M" "exec, ${
            getExe self.packages.${pkgs.stdenv.hostPlatform.system}.qs-music-search
          }" "Music search (YouTube)" "Menus")
          (kb "${altMod},M" "exec, ${
            getExe self.packages.${pkgs.stdenv.hostPlatform.system}.qs-music-local
          }" "Music search (local)" "Menus")
          (kb "${shiftMod},M"
            "exec, mpc status | grep -q 'playing' && mpc stop || { mpc clear && mpc add / && mpc shuffle && mpc play; }"
            "Toggle shuffle all / stop"
            "Menus"
          )
          (kb "${mod},C" "exec, ${
            getExe self.packages.${pkgs.stdenv.hostPlatform.system}.qs-checklist
          }" "Checklist" "Menus")
          (kb "${mod},X" "exec, dms ipc call powermenu toggle" "Power menu" "Menus")
          (kb "${mod},V" "exec, qs-tools" "Tools menu" "Menus")
        ];

        # ── Tools ──
        tools = [
          (kb "${shiftMod},V" "exec, stop-autoclickers" "Stop all autoclickers" "Tools")
          (kb "${altMod},V" "exec, ${
            getExe self.packages.${pkgs.stdenv.hostPlatform.system}.toggle-pause-autoclickers
          }" "Toggle pause autoclickers" "Tools")
          (kb "${shiftMod},Z" "exec, ${
            getExe self.packages.${pkgs.stdenv.hostPlatform.system}.qs-vpn
          }" "VPN selector" "Tools")
          (kb "${altSuperMod},M" "exec, ${
            getExe self.packages.${pkgs.stdenv.hostPlatform.system}.toggle-lyrics-overlay
          }" "Toggle lyrics overlay" "Tools")
          (kb "${mod},I" "exec, ${
            getExe self.packages.${pkgs.stdenv.hostPlatform.system}.dms-idle-inhibit
          } toggle" "Toggle persistent idle inhibitor" "Tools")
        ];

        # ── Accessibility ──
        accessibility = [
          (kb "${mod},T" "exec, voxtype record toggle" "Toggle Voxtype" "Accessibility")
          (kb "${shiftMod},T" "exec, voxtype record cancel" "Cancel Voxtype" "Accessibility")
          (kb "${mod},MINUS" "zoom-out" "Zoom out" "Accessibility")
          (kb "${mod},EQUAL" "zoom-in" "Zoom in" "Accessibility")
        ];

        # ── Help ──
        help = [
          (kb "${mod},H" "exec, ${
            getExe self.packages.${pkgs.stdenv.hostPlatform.system}.qs-keybinds
          }" "Show keybind help" "Help")
        ];

        # ── Capture ──
        capture = [
          (kb "${mod},PRINT" "exec, ${hyprScreenshotExe} area" "Screenshot area (save)" "Capture")
          (kb ",PRINT" "exec, ${hyprScreenshotExe} monitor" "Screenshot monitor (save)" "Capture")
          (kb "${shiftMod},PRINT" "exec, ${hyprScreenshotExe} ocr" "Screenshot to text (OCR)" "Capture")
          (kb "${mod},S" "exec, ${hyprScreenshotExe} edit" "Screenshot area (edit with Swappy)" "Capture")
          (kb "${mod},R" "exec, ${hyprScreenshotExe} record" "Start video recording" "Capture")
          (kb "${shiftMod},R" "exec, ${hyprScreenshotExe} stop-record" "Stop video recording" "Capture")
        ];

        # ── Capture (complex scripts) ──
        captureScripts = [
          {
            key = "${shiftMod},S";
            exec = "exec, ${hyprScreenshotExe} ocr";
            description = "OCR screenshot to clipboard";
            category = "Capture";
          }
          {
            key = "${altMod},S";
            exec = "exec, ${hyprScreenshotExe} qr";
            description = "QR code scan to clipboard";
            category = "Capture";
          }
        ];

        # ── Mouse bindings (bindm) ──
        mouse = [
          (kb "${mod},mouse:273" "resizewindow" "Resize window (drag)" "Windows")
          (kb "${mod},mouse:272" "movewindow" "Move window (drag)" "Windows")
        ];

        # ── Media keys (bindl - locked) ──
        media = [
          (kb ",XF86AudioMute" "exec, ${
            getExe self.packages.${pkgs.stdenv.hostPlatform.system}.sound-toggle
          }" "Toggle mute" "Media")
          (kb ",XF86AudioPlay" "exec, ${pkgs.playerctl}/bin/playerctl play-pause" "Play/Pause media" "Media")
          (kb ",XF86AudioNext" "exec, ${pkgs.playerctl}/bin/playerctl next" "Next track" "Media")
          (kb ",XF86AudioPrev" "exec, ${pkgs.playerctl}/bin/playerctl previous" "Previous track" "Media")
        ];

        # ── System (bindl - locked) ──
        system = [
          (kb ",switch:Lid Switch" "exec, dms ipc call lock lock" "Lock screen on lid close" "System")
          (kb ",switch:Lid Switch" "exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 0" "Mute on lid close"
            "System"
          )
          (kb ",XF86RFKill" "exec, ${disableAirplaneModeKeyExe}" "Disable airplane mode key" "System")
          (kb ",XF86WLAN" "exec, ${disableAirplaneModeKeyExe}" "Disable WiFi airplane mode key" "System")
        ];

        # ── Volume (bindle - repeat) ──
        volume = [
          (kb ",XF86AudioRaiseVolume" "exec, ${
            getExe self.packages.${pkgs.stdenv.hostPlatform.system}.sound-up
          }" "Volume up" "Media")
          (kb ",XF86AudioLowerVolume" "exec, ${
            getExe self.packages.${pkgs.stdenv.hostPlatform.system}.sound-down
          }" "Volume down" "Media")
          (kb "SHIFT,XF86AudioRaiseVolume" "exec, ${
            getExe self.packages.${pkgs.stdenv.hostPlatform.system}.sound-up-small
          }" "Volume up (small)" "Media")
          (kb "SHIFT,XF86AudioLowerVolume" "exec, ${
            getExe self.packages.${pkgs.stdenv.hostPlatform.system}.sound-down-small
          }" "Volume down (small)" "Media")
        ];

        # ── Brightness (bindle - repeat) ──
        brightness = [
          (kb ",XF86MonBrightnessUp"
            "exec, ${getExe pkgs.brightnessctl} set --device=${systemSettings.backlightDevice} 5%+"
            "Screen brightness up"
            "Brightness"
          )
          (kb ",XF86MonBrightnessDown"
            "exec, ${getExe pkgs.brightnessctl} set --device=${systemSettings.backlightDevice} 5%-"
            "Screen brightness down"
            "Brightness"
          )
          (kb "SHIFT,XF86MonBrightnessUp"
            "exec, ${getExe pkgs.brightnessctl} set --device=${systemSettings.backlightDevice} 1%+"
            "Screen brightness up (small)"
            "Brightness"
          )
          (kb "SHIFT,XF86MonBrightnessDown"
            "exec, ${getExe pkgs.brightnessctl} set --device=${systemSettings.backlightDevice} 1%-"
            "Screen brightness down (small)"
            "Brightness"
          )
          (kb ",XF86KbdBrightnessUp"
            "exec, ${getExe pkgs.brightnessctl} set --device=${systemSettings.keyboardBacklightDevice} 5%+"
            "Keyboard backlight up"
            "Brightness"
          )
          (kb ",XF86KbdBrightnessDown"
            "exec, ${getExe pkgs.brightnessctl} set --device=${systemSettings.keyboardBacklightDevice} 5%-"
            "Keyboard backlight down"
            "Brightness"
          )
          (kb "SHIFT,XF86KbdBrightnessUp"
            "exec, ${getExe pkgs.brightnessctl} set --device=${systemSettings.keyboardBacklightDevice} 1%+"
            "Keyboard backlight up (small)"
            "Brightness"
          )
          (kb "SHIFT,XF86KbdBrightnessDown"
            "exec, ${getExe pkgs.brightnessctl} set --device=${systemSettings.keyboardBacklightDevice} 1%-"
            "Keyboard backlight down (small)"
            "Brightness"
          )
        ];
      };

      # Flatten all keybinds into lists for hyprland config generation
      allBindKeybinds =
        keybinds.apps
        ++ keybinds.windows
        ++ keybinds.menus
        ++ keybinds.tools
        ++ keybinds.accessibility
        ++ keybinds.help
        ++ keybinds.capture
        ++ keybinds.captureScripts
        ++ keybinds.workspaces;

      luaString = builtins.toJSON;

      luaKeyName =
        key:
        let
          parts = lib.splitString "," key;
          hasSeparator = builtins.length parts > 1;
          modPart = lib.trim (builtins.head parts);
          keyPart = lib.trim (builtins.concatStringsSep "," (builtins.tail parts));
          luaMods = lib.trim (builtins.replaceStrings [ "_" " " ] [ " + " " + " ] modPart);
        in
        if !hasSeparator then
          builtins.replaceStrings [ "_" ] [ " + " ] key
        else if luaMods == "" then
          keyPart
        else
          "${luaMods} + ${keyPart}";

      luaBool = value: if value then "true" else "false";

      luaValue =
        value:
        if builtins.isBool value then
          luaBool value
        else if builtins.isInt value || builtins.isFloat value then
          toString value
        else
          luaString value;

      luaTable =
        attrs:
        "{ "
        + lib.concatStringsSep ", " (lib.mapAttrsToList (name: value: "${name} = ${luaValue value}") attrs)
        + " }";

      luaDirection =
        dir:
        {
          l = "left";
          r = "right";
          u = "up";
          d = "down";
        }
        .${dir} or dir;

      luaExecDispatcher = command: "hl.dsp.exec_cmd(${luaString command})";

      luaDispatcher =
        action:
        let
          trimmed = lib.trim action;
          after = prefix: lib.trim (lib.removePrefix prefix trimmed);
          afterComma = prefix: lib.trim (lib.removePrefix prefix trimmed);
          splitArgs = value: builtins.filter (part: part != "") (lib.splitString " " (lib.trim value));
        in
        if lib.hasPrefix "exec," trimmed then
          let
            command = after "exec,";
          in
          if command == "" then "hl.dsp.no_op()" else luaExecDispatcher command
        else if trimmed == "zoom-out" then
          "function() zoom_factor = math.max(1.0, zoom_factor - 0.1); hl.config({ cursor = { zoom_factor = zoom_factor } }) end"
        else if trimmed == "zoom-in" then
          "function() zoom_factor = zoom_factor + 0.1; hl.config({ cursor = { zoom_factor = zoom_factor } }) end"
        else if trimmed == "togglefloating," then
          "hl.dsp.window.float()"
        else if trimmed == "centerwindow" then
          "hl.dsp.window.center()"
        else if trimmed == "fullscreen" then
          "hl.dsp.window.fullscreen()"
        else if trimmed == "togglegroup" then
          "hl.dsp.group.toggle()"
        else if lib.hasPrefix "moveintogroup," trimmed then
          "hl.dsp.window.move({ into_group = ${luaString (luaDirection (afterComma "moveintogroup,"))} })"
        else if lib.hasPrefix "layoutmsg," trimmed then
          "hl.dsp.layout(${luaString (afterComma "layoutmsg,")})"
        else if trimmed == "pseudo" then
          "hl.dsp.window.pseudo()"
        else if lib.hasPrefix "movefocus," trimmed then
          "hl.dsp.focus({ direction = ${luaString (luaDirection (afterComma "movefocus,"))} })"
        else if lib.hasPrefix "movewindow, mon:" trimmed then
          "hl.dsp.window.move({ monitor = ${luaString (luaDirection (afterComma "movewindow, mon:"))} })"
        else if lib.hasPrefix "movewindow," trimmed then
          "hl.dsp.window.move({ direction = ${luaString (luaDirection (afterComma "movewindow,"))} })"
        else if lib.hasPrefix "swapwindow," trimmed then
          "hl.dsp.window.swap({ direction = ${luaString (luaDirection (afterComma "swapwindow,"))} })"
        else if lib.hasPrefix "focusmonitor," trimmed then
          "hl.dsp.focus({ monitor = ${luaString (luaDirection (afterComma "focusmonitor,"))} })"
        else if trimmed == "togglesplit," then
          ''hl.dsp.layout("togglesplit")''
        else if trimmed == "cyclenext," then
          "hl.dsp.window.cycle_next()"
        else if trimmed == "cyclenext, prev" then
          "hl.dsp.window.cycle_next({ next = false })"
        else if trimmed == "bringactivetotop" then
          "hl.dsp.window.bring_to_top()"
        else if lib.hasPrefix "resizeactive," trimmed then
          let
            args = splitArgs (afterComma "resizeactive,");
            x = builtins.elemAt args 0;
            y = builtins.elemAt args 1;
          in
          "hl.dsp.window.resize({ x = ${x}, y = ${y}, relative = true })"
        else if lib.hasPrefix "workspace," trimmed then
          "hl.dsp.focus({ workspace = ${luaString (afterComma "workspace,")} })"
        else if lib.hasPrefix "togglespecialworkspace," trimmed then
          "hl.dsp.workspace.toggle_special(${luaString (afterComma "togglespecialworkspace,")})"
        else if lib.hasPrefix "movetoworkspace," trimmed then
          "hl.dsp.window.move({ workspace = ${luaString (afterComma "movetoworkspace,")} })"
        else if lib.hasPrefix "focusworkspaceoncurrentmonitor," trimmed then
          "hl.dsp.focus({ workspace = ${luaString (afterComma "focusworkspaceoncurrentmonitor,")}, on_current_monitor = true })"
        else if trimmed == "resizewindow" then
          "hl.dsp.window.resize()"
        else if trimmed == "movewindow" then
          "hl.dsp.window.drag()"
        else if lib.hasPrefix "hyprctl " trimmed then
          luaExecDispatcher trimmed
        else
          throw "unsupported Hyprland dispatcher action: ${trimmed}";

      luaBind =
        flags: kb:
        let
          options = flags // {
            description = kb.description;
          };
        in
        "hl.bind(${luaString (luaKeyName kb.key)}, ${luaDispatcher kb.exec}, ${luaTable options})";

      luaEnv =
        entry:
        let
          parts = lib.splitString "," entry;
          name = builtins.head parts;
          value = builtins.concatStringsSep "," (builtins.tail parts);
        in
        "hl.env(${luaString name}, ${luaString value}, true)";

      luaBinds = lib.concatStringsSep "\n" (
        (map (luaBind { }) allBindKeybinds)
        ++ (map (luaBind { mouse = true; }) keybinds.mouse)
        ++ (map (luaBind { locked = true; }) (keybinds.media ++ keybinds.system))
        ++ (map (luaBind {
          locked = true;
          repeating = true;
        }) (keybinds.volume ++ keybinds.brightness))
        ++ (map (luaBind { repeating = true; }) keybinds.resize)
        ++ [ ''hl.bind("mouse:274", hl.dsp.no_op())'' ]
        ++ (builtins.concatLists (
          builtins.genList (
            i:
            let
              ws = i + 1;
            in
            [
              "hl.bind(${luaString "${mod} + code:1${toString i}"}, hl.dsp.focus({ workspace = ${luaString (toString ws)}, on_current_monitor = true }))"
              "hl.bind(${luaString "${mod} + SHIFT + code:1${toString i}"}, hl.dsp.window.move({ workspace = ${luaString (toString ws)} }))"
            ]
          ) 9
        ))
      );

      # Convert key from hyprland format to human-readable for help overlay
      humanizeKey =
        key:
        let
          # Replace common patterns
          replaced =
            builtins.replaceStrings
              [
                "${shiftAltSuperMod},"
                "${altSuperMod},"
                "${mod} CTRL,"
                "${mod},"
                "${shiftMod},"
                "${altMod},"
                "SHIFT,"
                ",XF86"
                "XF86"
                ",switch:"
                "switch:"
                ",PRINT"
                "PRINT"
                ",mouse:"
                "mouse:"
              ]
              [
                "SUPER + SHIFT + ALT + "
                "SUPER + ALT + "
                "SUPER + CTRL + "
                "SUPER + "
                "SUPER + SHIFT + "
                "ALT + "
                "SHIFT + "
                ""
                ""
                ""
                "Lid "
                ""
                "Print"
                "Mouse "
                "Mouse "
              ]
              key;
        in
        builtins.replaceStrings
          [
            "left"
            "right"
            "up"
            "down"
            "RETURN"
            "MINUS"
            "EQUAL"
            "backslash"
            "TAB"
            "mouse_down"
            "mouse_up"
          ]
          [
            "←"
            "→"
            "↑"
            "↓"
            "Return"
            "-"
            "="
            "\\"
            "Tab"
            "Scroll Down"
            "Scroll Up"
          ]
          replaced;

      # Generate keybindDescriptions from unified keybinds
      allKeybindDescriptions =
        let
          allKbs =
            allBindKeybinds
            ++ keybinds.mouse
            ++ keybinds.media
            ++ keybinds.system
            ++ keybinds.volume
            ++ keybinds.brightness
            ++ keybinds.resize;
        in
        map (kb: {
          key = humanizeKey kb.key;
          inherit (kb) description category;
        }) allKbs
        # Add workspace keybinds
        ++ [
          {
            key = "SUPER + 1-9";
            description = "Switch to workspace 1-9";
            category = "Workspaces";
          }
          {
            key = "SUPER + SHIFT + 1-9";
            description = "Move window to workspace 1-9";
            category = "Workspaces";
          }
        ];
    in
    {
      config = lib.mkIf (!kdeEnabled) {
        # Persist user-edited display/workspace files as durable config, not cache,
        # because DMS and nwg-displays both expect Hyprland to source them at login.
        impermanence.home.files = [
          ".config/hypr/monitors.conf"
          ".config/hypr/workspaces.conf"
        ];

        # Hyprland treats missing `source` targets as config errors, while
        # impermanence persists these editable files only after they exist. Create
        # missing placeholders without touching existing files: Hyprland watches
        # sourced paths and can autoreload while activation is still rewriting
        # configs, leaving defaults active until a later manual reload.
        system.activationScripts.hyprland-source-placeholders = {
          text = ''
            HYPR_DIR="${homeDirectory}/.config/hypr"
            HYPR_DMS_DIR="$HYPR_DIR/dms"
            mkdir -p "$HYPR_DMS_DIR"
            for source_file in "$HYPR_DIR/monitors.conf" "$HYPR_DIR/workspaces.conf" ${
              lib.concatMapStringsSep " " (fragment: ''"$HYPR_DMS_DIR/${fragment}"'') hyprDmsFragments
            }; do
              if [ ! -e "$source_file" ]; then
                install -D -m 0644 /dev/null "$source_file"
              fi
            done
            chown -R ${user}:users "$HYPR_DIR"
          '';
          deps = [ "users" ];
        };

        # Create the same placeholders during normal boot, before the user session
        # reads Hyprland's generated config. Source entries are below in this file.
        systemd.tmpfiles.rules = [
          "d ${homeDirectory}/.config/hypr 0755 ${user} users -"
          "f ${homeDirectory}/.config/hypr/monitors.conf 0644 ${user} users -"
          "f ${homeDirectory}/.config/hypr/workspaces.conf 0644 ${user} users -"
          "d ${homeDirectory}/.config/hypr/dms 0755 ${user} users -"
        ]
        ++ builtins.map (
          fragment: "f ${homeDirectory}/.config/hypr/dms/${fragment} 0644 ${user} users -"
        ) hyprDmsFragments;

        # Pesist the .current_wallpaper in wallpaper
        impermanence.home.cache.directories = [
          "wallpaper"
        ];

        # Autostart cliphist - a clipboard manager programme
        preferences.autostart = [
          "${pkgs.wl-clipboard}/bin/wl-paste --type text --watch ${pkgs.cliphist}/bin/cliphist store" # Stores text with original MIME metadata.
          "${pkgs.wl-clipboard}/bin/wl-paste --type image --watch ${pkgs.cliphist}/bin/cliphist store" # Stores images byte-for-byte for later image/png recopy.
          "${pkgs.kdePackages.kactivitymanagerd}/libexec/kactivitymanagerd"
        ];

        programs.hyprland = {
          enable = true;
          withUWSM = true;
        };

        home.programs.hyprland.enable = true;

        # Keybind descriptions generated from unified keybind definitions
        home.programs.hyprland.keybindDescriptions = allKeybindDescriptions;

        home.programs.hyprland.configType = "lua";
        home.programs.hyprland.luaConfig = ''
          -- Generated by nixconf. Hyprland 0.55+ uses Lua config; hyprlang is deprecated.
          -- Source docs: https://wiki.hypr.land/Configuring/Start/

          local function load_dms_outputs(path)
            local file = io.open(path, "r")
            if not file then
              return false
            end

            local loaded = false
            for line in file:lines() do
              local output, mode, position, scale = line:match("^%s*monitor%s*=%s*([^,]*),%s*([^,]*),%s*([^,]*),%s*([^,%s]*)")
              if output then
                hl.monitor({
                  output = output:gsub("^%s+", ""):gsub("%s+$", ""),
                  mode = mode:gsub("^%s+", ""):gsub("%s+$", ""),
                  position = position:gsub("^%s+", ""):gsub("%s+$", ""),
                  scale = scale:gsub("^%s+", ""):gsub("%s+$", ""),
                })
                loaded = true
              end
            end
            file:close()
            return loaded
          end

          local zoom_factor = 1.0

          -- DMS still writes Hyprland monitor fragments in legacy syntax. Do not
          -- source hyprlang from Lua; translate monitor lines or use the documented
          -- fallback rule for random monitors.
          -- Sources: Hyprland monitor Lua docs and DMS embedded outputs.conf path.
          if not load_dms_outputs(${luaString "${homeDirectory}/.config/hypr/dms/outputs.conf"}) then
            hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })
          end

          hl.config({
            xwayland = {
              force_zero_scaling = true,
            },
            general = {
              resize_on_border = true,
              extend_border_grab_area = 6,
              hover_icon_on_border = true,
              gaps_in = ${toString theme.gaps-in},
              gaps_out = ${toString theme.gaps-out},
              border_size = ${toString theme.border-size},
              layout = "dwindle",
              col = {
                active_border = "rgb(${colorsNoHash.border-color})",
                inactive_border = "rgb(${colorsNoHash.border-color-inactive})",
              },
            },
            group = {
              groupbar = {
                col = {
                  active = "rgb(${colorsNoHash.border-color})",
                  inactive = "rgb(${colorsNoHash.border-color-inactive})",
                },
              },
              col = {
                border_active = "rgb(${colorsNoHash.border-color})",
                border_inactive = "rgb(${colorsNoHash.border-color-inactive})",
              },
            },
            dwindle = {
              preserve_split = true,
              smart_split = true,
              smart_resizing = true,
              use_active_for_splits = true,
              permanent_direction_override = true,
              precise_mouse_move = true,
              special_scale_factor = 1.0,
            },
            master = {
              new_status = "master",
              allow_small_split = true,
              mfact = 0.5,
            },
            misc = {
              vrr = 1,
              disable_hyprland_logo = true,
              disable_splash_rendering = true,
              force_default_wallpaper = 0,
              disable_autoreload = false,
              middle_click_paste = false,
              focus_on_activate = true,
              on_focus_under_fullscreen = 2,
            },
            debug = {
              vfr = true,
            },
            input = {
              kb_layout = "gb",
              follow_mouse = 1,
              sensitivity = 0.5,
              repeat_delay = 300,
              repeat_rate = 50,
              numlock_by_default = true,
              touchpad = {
                natural_scroll = true,
                clickfinger_behavior = true,
              },
            },
            decoration = {
              rounding = ${toString theme.rounding},
              active_opacity = 1.0,
              inactive_opacity = ${toString theme.opacity},
              dim_inactive = false,
              dim_strength = 0.5,
              dim_around = 0.5,
              dim_special = 0.5,
              shadow = {
                enabled = false,
              },
              blur = {
                enabled = ${luaBool theme.blur},
                size = 2,
                passes = 3,
                new_optimizations = true,
                vibrancy = 0.1696,
              },
            },
            animations = {
              enabled = false,
            },
          })

          hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

          hl.window_rule({ match = { tag = "modal" }, float = true })
          hl.window_rule({ match = { tag = "modal" }, pin = true })
          hl.window_rule({ match = { tag = "modal" }, center = true })

          -- Flameshot creates a transient full-screen helper; keep it unmanaged.
          -- Source: https://wiki.hypr.land/FAQ/
          hl.window_rule({ match = { class = "^(flameshot)$" }, no_anim = true })
          hl.window_rule({ match = { class = "^(flameshot)$" }, float = true })
          hl.window_rule({ match = { class = "^(flameshot)$" }, move = { 0, 0 } })
          hl.window_rule({ match = { class = "^(flameshot)$" }, pin = true })

          hl.window_rule({ match = { class = "^(waydroid\\.InputMethod)$" }, float = true })
          hl.window_rule({ match = { class = "^(waydroid\\.InputMethod)$" }, no_focus = true })

          -- Quickshell layer-shell windows provide DMS shell surfaces.
          hl.layer_rule({ match = { namespace = "^quickshell$" }, blur = true })
          hl.layer_rule({ match = { namespace = "^quickshell$" }, ignore_alpha = 0.01 })

          ${lib.concatStringsSep "\n" (
            map luaEnv [
              "XDG_SESSION_TYPE,wayland"
              "XDG_SESSION_DESKTOP,Hyprland"
              "XDG_CURRENT_DESKTOP,Hyprland"
              "MOZ_ENABLE_WAYLAND,1"
              "ANKI_WAYLAND,1"
              "NIXOS_OZONE_WL,1"
              "ELECTRON_OZONE_PLATFORM_HINT,auto"
              "DISABLE_QT5_COMPAT,0"
              "GDK_BACKEND,wayland"
              "GDK_SCALE,2"
              "WLR_DRM_NO_ATOMIC,1"
              "QT_AUTO_SCREEN_SCALE_FACTOR,1"
              "QT_WAYLAND_DISABLE_WINDOWDECORATION,1"
              "QT_QPA_PLATFORM,wayland"
              "QT_QPA_PLATFORMTHEME,hyprqt6engine"
              "QT_QUICK_CONTROLS_STYLE,org.kde.desktop"
              "KDE_FULL_SESSION,true"
              "KDE_SESSION_VERSION,6"
              "WLR_BACKEND,vulkan"
              "WLR_RENDERER,vulkan"
              "WLR_NO_HARDWARE_CURSORS,1"
              "CLUTTER_BACKEND,wayland"
              "GSK_RENDERER,vulkan"
              "XCURSOR_THEME,Adwaita"
              "XCURSOR_SIZE,16"
              "CHECKLIST_DIR,/home/${config.preferences.user.username}/Shared/Checklist"
            ]
          )}

          ${luaBinds}
        '';

        environment.systemPackages = with pkgs; [
          wl-clipboard
          cliphist # Clipboard manager
          xdg-utils # Helps cliphist/wl-clipboard infer image MIME types.
          hyprScreenshot
          hyprClipboard
          disableAirplaneModeKey
          closeActiveWindow
          brightnessctl
          dconf # user-prefs
          adwaita-icon-theme # Provides the Adwaita cursor theme selected above

          hyprpolkitagent # Hyprland Polkit agent
          pkgs.kdePackages.polkit-kde-agent-1 # KDE Polkit agent

          mpc # music player controller
          playerctl # audio player controller

          quickshell # panels, widgets, etc
          wlrctl # wayland tools, e.g. autoclicking
          zbar # read qr codes
          tesseract5 # read text

          hyprpicker # color picker

          nwg-displays # displays/outputs settings gui

          # Utilities for eye & health protection not replaced by DMS.
          safeeyes # Intervalled-reminders to look around/take a break

          # Recordings
          grim
          grimblast
          slurp
          wf-recorder
          swappy

          networkmanagerapplet

          # Keyring
          pkgs.gnome-keyring
          pkgs.libsecret # contains secret-tool + provides the org.freedesktop.secrets service
          pkgs.seahorse # optional GUI to see/manage keyrings (very useful for debugging)
        ];

        # Enable Gnome Keyring
        services.gnome.gnome-keyring.enable = true;
      };
    };
}
