{
  inputs,
  ...
}:
{
  perSystem =
    {
      pkgs,
      self',
      lib,
      ...
    }:
    let
      # Helper to prepare QML files for the Nix store
      # Quickshell requires imports to be valid. We can't easily use absolute paths for imports
      # without file:// schema, and editing the source is messy.
      # Instead, we create a derivation that mimics the source structure:
      # $out/
      #   ├── script.qml
      #   └── lib -> /nix/store/.../lib
      # This allows 'import "./lib"' in the QML to work natively.
      mkQml =
        name: src:
        let
          env = pkgs.runCommandLocal "qs-${name}" { } ''
            mkdir -p $out
            ln -s ${./lib} $out/lib
            cp ${src} $out/${name}
            cp ${./list_apps.ts} $out/list_apps.ts 2>/dev/null || true
          '';
        in
        "${env}/${name}";
    in
    {
      packages.toggle-crosshair = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "toggle-crosshair" ''
          # Toggle QuickShell for crosshair.qml with slurp selection, using hyprctl dispatch exec to spawn

          QML_FILE="${mkQml "crosshair.qml" ./crosshair.qml}"
          QS_BIN="${pkgs.quickshell}/bin/qs"
          export QML2_IMPORT_PATH="${pkgs.qt6.qt5compat}/lib/qt-6/qml:$QML2_IMPORT_PATH"

          # Try to kill existing instance (toggling)
          if ! "$QS_BIN" kill -p "$QML_FILE"; then
              # No instance running → allow user to select a region
              geometry=$(
                  {
                      # 1. All mapped windows on active workspace
                      hyprctl clients -j | jq -r --argjson ws "$(hyprctl activeworkspace -j | jq '.id')" '
                          .[]
                          | select(.workspace.id == $ws and .mapped)
                          | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"
                      '
                      # 2. All layer surfaces on monitor with active workspace
                      hyprctl layers -j | jq -r --arg mon "$(hyprctl activeworkspace -j | jq -r '.monitor')" '
                          .[$mon] // {}
                          | .levels // []
                          | .[]
                          | .[]
                          | .[]
                          | select(.namespace != "")
                          | "\(.x),\(.y) \(.w)x\(.h)"
                      '
                  } | slurp -r
              )

              # Parse slurp output: "x,y wxh"
              pos=''${geometry%% *}   # extract "x,y"
              size=''${geometry#* }   # extract "wxh"

              IFS=',' read -r x y <<< "$pos"
              IFS='x' read -r w h <<< "$size"

              # Compute center
              center_x=$(( x + w / 2 ))
              center_y=$(( y + h / 2 ))

              # Launch QuickShell via hyprctl dispatch exec
              # Uses QML_FILE, passing X and Y coordinates.
              hyprctl dispatch exec "X=$center_x Y=$center_y \"$QS_BIN\" -p \"$QML_FILE\""
          fi
        '';
      };

      packages.toggle-lyrics-overlay = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "toggle-lyrics-overlay" ''
          # Toggle QuickShell lyrics overlay

          QML_FILE="${mkQml "lyrics-overlay.qml" ./lyrics-overlay.qml}"
          QS_BIN="${pkgs.quickshell}/bin/qs"
          export QML2_IMPORT_PATH="${pkgs.qt6.qt5compat}/lib/qt-6/qml:$QML2_IMPORT_PATH"

          case "''${1:-toggle}" in
            show)
              # Kill existing instance first
              "$QS_BIN" kill -p "$QML_FILE" 2>/dev/null || true
              # Launch with environment configuration
              OVERLAY_COMMAND="''${OVERLAY_COMMAND}" \
              LYRICS_LINES="''${LYRICS_LINES:-3}" \
              LYRICS_POSITION="''${LYRICS_POSITION:-bottom}" \
              LYRICS_FONT_SIZE="''${LYRICS_FONT_SIZE:-28}" \
              LYRICS_COLOR="''${LYRICS_COLOR:-#ffffff}" \
              LYRICS_OPACITY="''${LYRICS_OPACITY:-0.95}" \
              LYRICS_SHADOW="''${LYRICS_SHADOW:-true}" \
              LYRICS_UPDATE_INTERVAL="''${LYRICS_UPDATE_INTERVAL:-400}" \
              LYRICS_SPACING="''${LYRICS_SPACING:-8}" \
              LYRICS_LENGTH="''${LYRICS_LENGTH:-0}" \
              "$QS_BIN" -p "$QML_FILE" &
              ;;
            hide)
              "$QS_BIN" kill -p "$QML_FILE"
              ;;
            *)  # toggle
              if ! "$QS_BIN" kill -p "$QML_FILE" 2>/dev/null; then
                OVERLAY_COMMAND="''${OVERLAY_COMMAND}" \
                LYRICS_LINES="''${LYRICS_LINES:-3}" \
                LYRICS_POSITION="''${LYRICS_POSITION:-bottom}" \
                LYRICS_FONT_SIZE="''${LYRICS_FONT_SIZE:-28}" \
                LYRICS_COLOR="''${LYRICS_COLOR:-#ffffff}" \
                LYRICS_OPACITY="''${LYRICS_OPACITY:-0.95}" \
                LYRICS_SHADOW="''${LYRICS_SHADOW:-true}" \
                LYRICS_UPDATE_INTERVAL="''${LYRICS_UPDATE_INTERVAL:-400}" \
                LYRICS_SPACING="''${LYRICS_SPACING:-8}" \
                LYRICS_LENGTH="''${LYRICS_LENGTH:-0}" \
                "$QS_BIN" -p "$QML_FILE" &
              fi
              ;;
          esac
        '';

        runtimeInputs = [
          pkgs.quickshell
        ];
      };

      packages.qs-launcher = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package =
          let
            launcherQml = mkQml "launcher.qml" ./launcher.qml;
            # Extract the directory from the QML path
            launcherDir = builtins.dirOf launcherQml;
          in
          pkgs.writeShellScriptBin "qs-launcher" ''
            # Launch QuickShell Launcher
            # Usage: qs-launcher [--calc]

            MODE="app"
            if [[ "$1" == "--calc" ]]; then
                MODE="calc"
            fi

            QML_FILE="${launcherQml}"
            QS_BIN="${pkgs.quickshell}/bin/qs"
            export QML2_IMPORT_PATH="${pkgs.qt6.qt5compat}/lib/qt-6/qml:$QML2_IMPORT_PATH"

            LAUNCHER_MODE="$MODE" \
            LAUNCHER_SCRIPT_DIR="${launcherDir}" \
            "$QS_BIN" -p "$QML_FILE" &
          '';
        runtimeInputs = [
          pkgs.quickshell
          pkgs.libqalculate
          pkgs.bun
        ];
      };

      packages.qs-emoji = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "qs-emoji" ''
          # Quickshell Emoji Picker (using qs-dmenu)
          # Fetches GitHub's gemoji database and allows selection/copy

          CACHE_FILE="$HOME/.cache/qs-emoji.txt"

          if [ ! -f "$CACHE_FILE" ]; then
              notify-send "Downloading Emoji List..."
              curl -sL "https://raw.githubusercontent.com/github/gemoji/master/db/emoji.json" | \
              jq -r '.[] | "\(.emoji) \(.aliases[0])"' > "$CACHE_FILE"
          fi

          # Verify cache file has content
          if [ ! -s "$CACHE_FILE" ]; then
              notify-send "Error" "Failed to download emoji list"
              rm -f "$CACHE_FILE"
              exit 1
          fi

          SELECTED=$(${lib.getExe self'.packages.qs-dmenu} -p "Emoji" < "$CACHE_FILE")

          if [ -n "$SELECTED" ]; then
              EMOJI=$(echo "$SELECTED" | cut -d' ' -f1)
              if [ -n "$EMOJI" ]; then
                  printf '%s' "$EMOJI" | wl-copy --type text/plain
                  notify-send "Copied" "$EMOJI"
              fi
          fi
        '';
        runtimeInputs = [
          self'.packages.qs-dmenu
          pkgs.curl
          pkgs.jq
          pkgs.wl-clipboard
          pkgs.libnotify
          pkgs.coreutils
        ];
      };

      packages.qs-nerd = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "qs-nerd" ''
          # Quickshell Nerd Font Picker (using qs-dmenu)
          # Fetches nerd font glyphs and allows selection/copy

          CACHE_FILE="$HOME/.cache/qs-nerd.txt"

          if [ ! -f "$CACHE_FILE" ]; then
              notify-send "Downloading Nerd Font List..."
              # Using nerd-fonts cheat sheet API which has cleaner data
              # Strip any ANSI codes and filter to valid icon entries
              curl -sL "https://raw.githubusercontent.com/ryanoasis/nerd-fonts/master/glyphnames.json" | \
              jq -r 'to_entries | .[] | select(.value.char != null) | "\(.value.char) \(.key)"' | \
              sed 's/\x1b\[[0-9;]*m//g' | \
              grep -v '^[[:space:]]*$' > "$CACHE_FILE"
          fi

          # Verify cache file has content
          if [ ! -s "$CACHE_FILE" ]; then
              notify-send "Error" "Failed to download nerd font list"
              rm -f "$CACHE_FILE"
              exit 1
          fi

          SELECTED=$(${lib.getExe self'.packages.qs-dmenu} -p "Icons" < "$CACHE_FILE")

          if [ -n "$SELECTED" ]; then
              ICON=$(echo "$SELECTED" | cut -d' ' -f1)
              if [ -n "$ICON" ]; then
                  printf '%s' "$ICON" | wl-copy --type text/plain
                  notify-send "Copied" "$ICON"
              fi
          fi
        '';
        runtimeInputs = [
          self'.packages.qs-dmenu
          pkgs.curl
          pkgs.jq
          pkgs.gnused
          pkgs.gnugrep
          pkgs.wl-clipboard
          pkgs.libnotify
          pkgs.coreutils
        ];
      };

      packages.qs-dock = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "qs-dock" ''
          # Launch QuickShell Dock

          QML_FILE="${mkQml "dock.qml" ./dock.qml}"
          QS_BIN="${pkgs.quickshell}/bin/qs"
          export QML2_IMPORT_PATH="${pkgs.qt6.qt5compat}/lib/qt-6/qml:$QML2_IMPORT_PATH"

          # Add icon themes to XDG_DATA_DIRS
          export XDG_DATA_DIRS="${pkgs.adwaita-icon-theme}/share:${pkgs.papirus-icon-theme}/share:$XDG_DATA_DIRS"

          # Kill if running to restart/toggle
          "$QS_BIN" kill -p "$QML_FILE" 2>/dev/null || true

          exec "$QS_BIN" -p "$QML_FILE"
        '';
        runtimeInputs = [
          pkgs.quickshell
          pkgs.adwaita-icon-theme
          pkgs.papirus-icon-theme
        ];
      };

      packages.qs-dmenu = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "qs-dmenu" ''
          # Quickshell dmenu replacement
          # Usage: echo "option1\noption2" | qs-dmenu [options]
          #
          # Options:
          #   -p, --prompt TEXT      Set prompt text (default: "Select")
          #   -l, --lines N          Number of visible lines (default: 15)
          #   -i                     Case insensitive matching
          #   -password              Password/hidden input mode
          #   -selected N            Pre-select item at index N
          #   -placeholder TEXT      Placeholder text for input
          #   -filter MODE           Filter mode: fuzzy, prefix, exact (default: fuzzy)
          #   -dmenu                 Ignored (compatibility)

          PROMPT="Select"
          LINES=15
          PASSWORD="false"
          CASE_INSENSITIVE="true"
          SELECTED=0
          PLACEHOLDER=""
          FILTER="fuzzy"
          MESSAGE=""

          # Parse args
          while [[ $# -gt 0 ]]; do
            case $1 in
              -p|--prompt)
                PROMPT="$2"
                shift 2
                ;;
              -l|--lines)
                LINES="$2"
                shift 2
                ;;
              -i)
                CASE_INSENSITIVE="true"
                shift
                ;;
              -I)
                CASE_INSENSITIVE="false"
                shift
                ;;
              -password)
                PASSWORD="true"
                shift
                ;;
              -selected)
                SELECTED="$2"
                shift 2
                ;;
              -placeholder)
                PLACEHOLDER="$2"
                shift 2
                ;;
              -filter)
                FILTER="$2"
                shift 2
                ;;
              -mesg)
                MESSAGE="$2"
                shift 2
                ;;
              -dmenu|-matching|-no-custom|-markup-rows)
                # Ignored flags for rofi compatibility
                shift
                ;;
              *)
                shift
                ;;
            esac
          done

          # Save stdin to temp file
          INPUT_FILE=$(mktemp)
          cat > "$INPUT_FILE"

          QML_FILE="${mkQml "dmenu.qml" ./dmenu.qml}"
          QS_BIN="${pkgs.quickshell}/bin/qs"
          export QML2_IMPORT_PATH="${pkgs.qt6.qt5compat}/lib/qt-6/qml:$QML2_IMPORT_PATH"

          # Run Quickshell and capture stdout
          # We filter for our specific result prefix to ignore all logs
          DMENU_INPUT_FILE="$INPUT_FILE" \
          DMENU_PROMPT="$PROMPT" \
          DMENU_LINES="$LINES" \
          DMENU_PASSWORD="$PASSWORD" \
          DMENU_CASE_INSENSITIVE="$CASE_INSENSITIVE" \
          DMENU_SELECTED="$SELECTED" \
          DMENU_PLACEHOLDER="$PLACEHOLDER" \
          DMENU_FILTER="$FILTER" \
          DMENU_MESSAGE="$MESSAGE" \
          "$QS_BIN" -p "$QML_FILE" 2>&1 | grep "QS_DMENU_RESULT:" | sed 's/^.*QS_DMENU_RESULT://'

          # Cleanup
          rm -f "$INPUT_FILE"
        '';
        runtimeInputs = [
          pkgs.quickshell
          pkgs.coreutils
          pkgs.gnused
        ];
      };

      packages.qs-askpass = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "qs-askpass" ''
          # Quickshell askpass (password prompt)
          # Usage: qs-askpass "Prompt"

          PROMPT="''${1:-Password:}"

          # We feed empty input to dmenu but enable password mode
          echo "" | ${lib.getExe self'.packages.qs-dmenu} -p "$PROMPT" -password
        '';
        runtimeInputs = [ self'.packages.qs-dmenu ];
      };
      packages.qs-powermenu = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "qs-powermenu" ''
          # Quickshell Power Menu

          options=(
            "󰌾 Lock"
            "󰍃 Logout"
            " Suspend"
            "󰑐 Reboot"
            "󰿅 Shutdown"
          )

          # Join options with newlines
          options_str=$(printf "%s\n" "''${options[@]}")

          selected=$(echo "$options_str" | ${lib.getExe self'.packages.qs-dmenu} -p "Power Menu")

          if [ -z "$selected" ]; then
            exit 0
          fi

          # Remove icon (first 2 chars + space)
          action="''${selected:2}"
          # Trim leading space if any (though slice usually handles it if icon+space is constant)
          action=$(echo "$action" | xargs)

          case "$action" in
            "Lock")
              ${pkgs.hyprlock}/bin/hyprlock
              ;;
            "Logout")
              hyprctl dispatch exit
              ;;
            "Suspend")
              systemctl suspend
              ;;
            "Reboot")
              systemctl reboot
              ;;
            "Shutdown")
              systemctl poweroff
              ;;
          esac
        '';
        runtimeInputs = [
          self'.packages.qs-dmenu
          pkgs.hyprlock
        ];
      };

      packages.qs-vpn = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "qs-vpn" ''
          # Quickshell VPN Toggle (AirVPN via NetworkManager)
          # Usage: qs-vpn [connect|disconnect|toggle|status]

          VPN_NAME="AirVPN"
          # OVPN config path is set via environment variable from networking.nix
          OVPN_CONFIG="''${AIRVPN_OVPN_PATH:-}"

          # Check if VPN connection exists in NetworkManager
          vpn_exists() {
            nmcli connection show "$VPN_NAME" &>/dev/null
          }

          # Check if VPN is currently active
          vpn_active() {
            nmcli connection show --active | grep -q "$VPN_NAME"
          }

          # Import VPN config if not already imported
          ensure_vpn_imported() {
            if ! vpn_exists; then
              if [ -n "$OVPN_CONFIG" ] && [ -f "$OVPN_CONFIG" ]; then
                notify-send "VPN" "Importing AirVPN configuration..."
                if nmcli connection import type openvpn file "$OVPN_CONFIG"; then
                  # Rename to friendly name
                  nmcli connection modify "$(basename "$OVPN_CONFIG" .ovpn)" connection.id "$VPN_NAME" 2>/dev/null || true
                  notify-send "VPN" "Configuration imported successfully"
                else
                  notify-send -u critical "VPN Error" "Failed to import VPN configuration"
                  exit 1
                fi
              else
                notify-send -u critical "VPN Error" "OVPN config not found. Check AIRVPN_OVPN_PATH env var."
                exit 1
              fi
            fi
          }

          connect_vpn() {
            ensure_vpn_imported
            if vpn_active; then
              notify-send "VPN" "Already connected to $VPN_NAME"
            else
              notify-send "VPN" "Connecting to $VPN_NAME..."
              if nmcli connection up "$VPN_NAME"; then
                notify-send "VPN" "Connected to $VPN_NAME"
              else
                notify-send -u critical "VPN Error" "Failed to connect to $VPN_NAME"
              fi
            fi
          }

          disconnect_vpn() {
            if vpn_active; then
              notify-send "VPN" "Disconnecting from $VPN_NAME..."
              if nmcli connection down "$VPN_NAME"; then
                notify-send "VPN" "Disconnected from $VPN_NAME"
              else
                notify-send -u critical "VPN Error" "Failed to disconnect from $VPN_NAME"
              fi
            else
              notify-send "VPN" "Not connected to $VPN_NAME"
            fi
          }

          toggle_vpn() {
            ensure_vpn_imported
            if vpn_active; then
              disconnect_vpn
            else
              connect_vpn
            fi
          }

          show_status() {
            if vpn_active; then
              echo "connected"
              notify-send "VPN Status" "Connected to $VPN_NAME"
            else
              echo "disconnected"
              notify-send "VPN Status" "Not connected to $VPN_NAME"
            fi
          }

          case "''${1:-toggle}" in
            connect)
              connect_vpn
              ;;
            disconnect)
              disconnect_vpn
              ;;
            toggle)
              toggle_vpn
              ;;
            status)
              show_status
              ;;
            *)
              echo "Usage: qs-vpn [connect|disconnect|toggle|status]"
              exit 1
              ;;
          esac
        '';
        runtimeInputs = [
          pkgs.networkmanager
          pkgs.libnotify
          pkgs.gnugrep
          pkgs.coreutils
        ];
      };

      packages.qs-keybinds = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "qs-keybinds" ''
          # Quickshell Keybind Help (using qs-dmenu)
          # Reads keybinds from ~/.config/hypr/keybinds.json and displays them

          KEYBINDS_FILE="$HOME/.config/hypr/keybinds.json"

          if [ ! -f "$KEYBINDS_FILE" ]; then
            notify-send -u critical "Keybind Help" "Keybinds file not found at $KEYBINDS_FILE"
            exit 1
          fi

          # Format keybinds for display: "KEY → Description"
          # Using jq to parse JSON and format nicely
          FORMATTED=$(jq -r '.[] | "\(.key)  ›  \(.description)"' "$KEYBINDS_FILE" | sort)

          if [ -z "$FORMATTED" ]; then
            notify-send "Keybind Help" "No keybinds configured"
            exit 0
          fi

          # Display using qs-dmenu (read-only, just for viewing)
          echo "$FORMATTED" | ${lib.getExe self'.packages.qs-dmenu} -p "Keybinds" -mesg "Press Enter to dismiss"
        '';
        runtimeInputs = [
          self'.packages.qs-dmenu
          pkgs.jq
          pkgs.libnotify
          pkgs.coreutils
        ];
      };
    };
}
