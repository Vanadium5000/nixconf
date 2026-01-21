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
        package = pkgs.writeShellScriptBin "qs-launcher" ''
          # Launch QuickShell Launcher
          # Usage: qs-launcher [--calc]

          MODE="app"
          if [[ "$1" == "--calc" ]]; then
              MODE="calc"
          fi

          QML_FILE="${mkQml "launcher.qml" ./launcher.qml}"
          QS_BIN="${pkgs.quickshell}/bin/qs"
          export QML2_IMPORT_PATH="${pkgs.qt6.qt5compat}/lib/qt-6/qml:$QML2_IMPORT_PATH"

          LAUNCHER_MODE="$MODE" "$QS_BIN" -p "$QML_FILE" &
        '';
        runtimeInputs = [
          pkgs.quickshell
          pkgs.libqalculate
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
                  printf '%s' "$EMOJI" | wl-copy
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
                  printf '%s' "$ICON" | wl-copy
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

          # Kill if running to restart/toggle
          "$QS_BIN" kill -p "$QML_FILE" 2>/dev/null || true

          "$QS_BIN" -p "$QML_FILE" &
        '';
        runtimeInputs = [ pkgs.quickshell ];
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
          DMENU_INPUT_FILE="$INPUT_FILE" \
          DMENU_PROMPT="$PROMPT" \
          DMENU_LINES="$LINES" \
          DMENU_PASSWORD="$PASSWORD" \
          DMENU_CASE_INSENSITIVE="$CASE_INSENSITIVE" \
          DMENU_SELECTED="$SELECTED" \
          DMENU_PLACEHOLDER="$PLACEHOLDER" \
          DMENU_FILTER="$FILTER" \
          "$QS_BIN" -p "$QML_FILE" 2>/dev/null | sed 's/^qml: //g'

          # Cleanup
          rm -f "$INPUT_FILE"
        '';
        runtimeInputs = [ pkgs.quickshell pkgs.coreutils pkgs.gnused ];
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
    };
}
