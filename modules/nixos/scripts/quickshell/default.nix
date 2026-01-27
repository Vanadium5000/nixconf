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
          # Quickshell VPN Selector - Multi-config with flag emojis
          # Opens qs-dmenu to select VPN from ~/Shared/VPNs/*.ovpn

          VPN_DIR="''${VPN_DIR:-$HOME/Shared/VPNs}"

          # Country code to flag emoji mapping (ISO 3166-1 alpha-2)
          declare -A FLAGS=(
            [us]="🇺🇸" [gb]="🇬🇧" [uk]="🇬🇧" [de]="🇩🇪" [fr]="🇫🇷" [nl]="🇳🇱" [ca]="🇨🇦"
            [au]="🇦🇺" [jp]="🇯🇵" [sg]="🇸🇬" [ch]="🇨🇭" [se]="🇸🇪" [no]="🇳🇴" [fi]="🇫🇮"
            [it]="🇮🇹" [es]="🇪🇸" [br]="🇧🇷" [mx]="🇲🇽" [in]="🇮🇳" [kr]="🇰🇷" [hk]="🇭🇰"
            [ie]="🇮🇪" [at]="🇦🇹" [be]="🇧🇪" [dk]="🇩🇰" [pl]="🇵🇱" [cz]="🇨🇿" [ro]="🇷🇴"
            [za]="🇿🇦" [nz]="🇳🇿" [ar]="🇦🇷" [cl]="🇨🇱" [co]="🇨🇴" [pt]="🇵🇹" [ru]="🇷🇺"
            [bg]="🇧🇬" [hr]="🇭🇷" [cy]="🇨🇾" [ee]="🇪🇪" [gr]="🇬🇷" [hu]="🇭🇺" [is]="🇮🇸"
            [lv]="🇱🇻" [lt]="🇱🇹" [lu]="🇱🇺" [mt]="🇲🇹" [md]="🇲🇩" [me]="🇲🇪" [mk]="🇲🇰"
            [rs]="🇷🇸" [sk]="🇸🇰" [si]="🇸🇮" [ua]="🇺🇦" [tr]="🇹🇷" [il]="🇮🇱" [ae]="🇦🇪"
            [th]="🇹🇭" [vn]="🇻🇳" [my]="🇲🇾" [ph]="🇵🇭" [id]="🇮🇩" [tw]="🇹🇼" [cn]="🇨🇳"
          )

          # Get flag emoji for country code
          get_flag() {
            local code="''${1,,}"  # lowercase
            echo "''${FLAGS[$code]:-❓}"
          }

          # Extract country code from filename
          # Handles: "AirVPN GB London Alathfar", "AirVPN_AT_Vienna", "us-server", "UK_London"
          get_country_code() {
            local filename="$1"
            local basename
            basename=$(basename "$filename" .ovpn)
            
            # Pattern 1: Standalone 2-letter code surrounded by separators
            # e.g., "AirVPN_AT_Vienna" or "AirVPN AT Vienna" -> "AT"
            if [[ "$basename" =~ [_[:space:]]([A-Z]{2})[_[:space:]] ]]; then
              echo "''${BASH_REMATCH[1]}"
              return
            fi
            
            # Pattern 2: "Provider CC City" format (code followed by space+word)
            # e.g., "AirVPN GB London Alathfar" -> "GB"
            if [[ "$basename" =~ [_[:space:]]([A-Z]{2})[[:space:]][A-Z] ]]; then
              echo "''${BASH_REMATCH[1]}"
              return
            fi
            
            # Pattern 3: Country code at start with separator (e.g., "us-server", "UK_London")
            if [[ "$basename" =~ ^([a-zA-Z]{2})[-_[:space:]] ]]; then
              echo "''${BASH_REMATCH[1]}"
              return
            fi
            
            # Pattern 4: Known codes as whole words only (word boundaries)
            local upper_name="''${basename^^}"
            upper_name="''${upper_name//[-_]/ }"  # normalize separators to spaces
            for code in GB UK US CA AU NZ DE FR NL BE AT CH SE NO FI DK IE IT ES PT PL CZ RO BG HR HU GR SI SK LT LV EE LU MT IS UA RS ME MK MD CY TR RU JP KR SG HK TW CN TH VN MY PH ID IN IL AE BR MX AR CL CO ZA; do
              # Match as whole word: start/space before, space/end after
              if [[ " $upper_name " == *" $code "* ]]; then
                echo "$code"
                return
              fi
            done
            
            # Fallback: first 2 chars
            echo "''${basename:0:2}"
          }

          # Get friendly name from ovpn filename
          get_display_name() {
            local filepath="$1"
            local basename
            basename=$(basename "$filepath" .ovpn)
            # Replace dashes/underscores with spaces for readability
            basename="''${basename//-/ }"
            basename="''${basename//_/ }"
            echo "$basename"
          }

          # Check if VPN connection exists in NetworkManager
          vpn_exists() {
            nmcli connection show "$1" &>/dev/null
          }

          # Get currently active VPN connection name (full name with spaces)
          get_active_vpn() {
            # Get VPN connections that are currently active - extract full NAME field
            nmcli -t -f NAME,TYPE connection show --active | grep ':vpn$' | cut -d: -f1 | head -1
          }

          # Import and configure VPN for persistence
          import_vpn() {
            local ovpn_file="$1"
            local vpn_name="$2"

            if ! vpn_exists "$vpn_name"; then
              notify-send "VPN" "Importing $vpn_name..."
              if nmcli connection import type openvpn file "$ovpn_file"; then
                # Rename to friendly name and enable autoconnect for persistence
                local imported_name
                imported_name=$(basename "$ovpn_file" .ovpn)
                nmcli connection modify "$imported_name" connection.id "$vpn_name" 2>/dev/null || true
                nmcli connection modify "$vpn_name" connection.autoconnect yes 2>/dev/null || true
                nmcli connection modify "$vpn_name" connection.autoconnect-retries 0 2>/dev/null || true
                notify-send "VPN" "$vpn_name imported successfully"
              else
                notify-send -u critical "VPN Error" "Failed to import $vpn_name"
                return 1
              fi
            fi
          }

          # Connect to VPN
          connect_vpn() {
            local vpn_name="$1"
            notify-send "VPN" "Connecting to $vpn_name..."
            if nmcli connection up "$vpn_name"; then
              notify-send "VPN" "Connected to $vpn_name"
            else
              notify-send -u critical "VPN Error" "Failed to connect to $vpn_name"
            fi
          }

          # Disconnect from VPN
          disconnect_vpn() {
            local vpn_name="$1"
            notify-send "VPN" "Disconnecting from $vpn_name..."
            if nmcli connection down "$vpn_name"; then
              notify-send "VPN" "Disconnected from $vpn_name"
            else
              notify-send -u critical "VPN Error" "Failed to disconnect from $vpn_name"
            fi
          }

          # Cache location (RAM-backed tmpfs for speed)
          CACHE_DIR="/dev/shm/qs-vpn-$UID"
          CACHE_FILE="$CACHE_DIR/vpn-cache"
          
          # Check if cache is valid (VPN dir hasn't changed)
          cache_valid() {
            [ -f "$CACHE_FILE" ] || return 1
            [ -d "$VPN_DIR" ] || return 1
            
            # Compare cache mtime with VPN dir mtime
            local cache_mtime dir_mtime
            cache_mtime=$(stat -c %Y "$CACHE_FILE" 2>/dev/null) || return 1
            dir_mtime=$(stat -c %Y "$VPN_DIR" 2>/dev/null) || return 1
            
            # Also check newest .ovpn file
            local newest_file
            newest_file=$(find "$VPN_DIR" -name "*.ovpn" -type f -printf '%T@\n' 2>/dev/null | sort -rn | head -1)
            [ -n "$newest_file" ] || return 1
            
            # Cache valid if newer than both dir and newest file
            [[ "$cache_mtime" -gt "$dir_mtime" ]] && [[ "$cache_mtime" -gt "''${newest_file%.*}" ]]
          }
          
          # Build and cache VPN entries
          build_cache() {
            mkdir -p "$CACHE_DIR"
            
            mapfile -t OVPN_FILES < <(find "$VPN_DIR" -name "*.ovpn" -type f 2>/dev/null | sort)
            
            if [ ''${#OVPN_FILES[@]} -eq 0 ]; then
              return 1
            fi
            
            # Build cache: "flag|display_name|filepath" per line
            : > "$CACHE_FILE"
            for ovpn_file in "''${OVPN_FILES[@]}"; do
              country_code=$(get_country_code "$ovpn_file")
              flag=$(get_flag "$country_code")
              display_name=$(get_display_name "$ovpn_file")
              echo "$flag|$display_name|$ovpn_file" >> "$CACHE_FILE"
            done
          }
          
          # Load entries from cache into arrays
          load_from_cache() {
            declare -gA FILE_MAP
            declare -gA NAME_MAP
            MENU_ENTRIES=""
            
            while IFS='|' read -r flag display_name filepath; do
              [ -z "$flag" ] && continue
              
              # Mark active VPN
              if [ -n "$ACTIVE_VPN" ] && [ "$display_name" = "$ACTIVE_VPN" ]; then
                entry="$flag $display_name ✓"
              else
                entry="$flag $display_name"
              fi
              
              MENU_ENTRIES+="$entry"$'\n'
              FILE_MAP["$flag $display_name"]="$filepath"
              NAME_MAP["$flag $display_name"]="$display_name"
            done < "$CACHE_FILE"
          }

          # Main logic
          main() {
            # Ensure VPN directory exists
            mkdir -p "$VPN_DIR"
            
            # Get currently active VPN first (needed for menu building)
            ACTIVE_VPN=$(get_active_vpn)
            
            # Use cache if valid, otherwise rebuild
            if ! cache_valid; then
              if ! build_cache; then
                notify-send "VPN" "No .ovpn files found in $VPN_DIR\nAdd your VPN configs there."
                exit 0
              fi
            fi
            
            # Load from cache
            declare -A FILE_MAP
            declare -A NAME_MAP
            load_from_cache

            # Add disconnect option if connected
            if [ -n "$ACTIVE_VPN" ]; then
              MENU_ENTRIES="🔌 Disconnect ($ACTIVE_VPN)"$'\n'"$MENU_ENTRIES"
            fi

            # Show menu
            SELECTION=$(echo -e "$MENU_ENTRIES" | qs-dmenu -p "VPN")

            [ -z "$SELECTION" ] && exit 0

            # Handle disconnect
            if [[ "$SELECTION" == "🔌 Disconnect"* ]]; then
              disconnect_vpn "$ACTIVE_VPN"
              exit 0
            fi

            # Get selected file (strip checkmark suffix if present)
            CLEAN_SELECTION="''${SELECTION% ✓}"
            SELECTED_FILE="''${FILE_MAP[$CLEAN_SELECTION]}"
            VPN_NAME="''${NAME_MAP[$CLEAN_SELECTION]}"

            if [ -z "$SELECTED_FILE" ]; then
              notify-send -u critical "VPN Error" "Could not find config for: $SELECTION"
              exit 1
            fi

            # If already connected to this VPN, disconnect
            if [ -n "$ACTIVE_VPN" ] && [ "$VPN_NAME" = "$ACTIVE_VPN" ]; then
              disconnect_vpn "$VPN_NAME"
              exit 0
            fi

            # Disconnect from current VPN if any
            if [ -n "$ACTIVE_VPN" ]; then
              nmcli connection down "$ACTIVE_VPN" 2>/dev/null || true
            fi

            # Import if needed and connect
            import_vpn "$SELECTED_FILE" "$VPN_NAME"
            connect_vpn "$VPN_NAME"
          }

          main
        '';
        runtimeInputs = [
          pkgs.networkmanager
          pkgs.libnotify
          pkgs.gnugrep
          pkgs.coreutils
          pkgs.findutils
          pkgs.gawk
          self'.packages.qs-dmenu
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
