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
      #   ├── lib -> /nix/store/.../lib
      #   └── notifications -> /nix/store/.../notifications (for notification center)
      # This allows 'import "./lib"' in the QML to work natively.
      mkQml =
        name: src:
        let
          env = pkgs.runCommandLocal "qs-${name}" { } ''
            mkdir -p $out
            ln -s ${./lib} $out/lib
            ln -s ${./notifications} $out/notifications 2>/dev/null || true
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

      packages.toggle-dictation-overlay = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "toggle-dictation-overlay" ''
          # Toggle QuickShell dictation overlay

          QML_FILE="${mkQml "dictation-overlay.qml" ./dictation-overlay.qml}"
          QS_BIN="${pkgs.quickshell}/bin/qs"
          export QML2_IMPORT_PATH="${pkgs.qt6.qt5compat}/lib/qt-6/qml:$QML2_IMPORT_PATH"

          case "''${1:-toggle}" in
            show)
              # Kill existing instance first
              "$QS_BIN" kill -p "$QML_FILE" 2>/dev/null || true
              "$QS_BIN" -p "$QML_FILE" &
              ;;
            hide)
              "$QS_BIN" kill -p "$QML_FILE"
              ;;
            *)  # toggle
              if ! "$QS_BIN" kill -p "$QML_FILE" 2>/dev/null; then
                "$QS_BIN" -p "$QML_FILE" &
              fi
              ;;
          esac
        '';
        runtimeInputs = [
          pkgs.coreutils
          pkgs.quickshell
        ];
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

      packages.qs-emoji = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "qs-emoji" ''
          # Quickshell Emoji Picker (using qs-dmenu)
          # Uses emojilib for rich keyword search (8-17 keywords per emoji)

          CACHE_FILE="$HOME/.cache/qs-emoji.txt"

          if [ ! -f "$CACHE_FILE" ]; then
              notify-send "Downloading Emoji List..."
              # emojilib provides many keywords per emoji for better search
              # Format: "😀 grinning_face face smile happy joy :D grin smiley"
              curl -sL "https://raw.githubusercontent.com/muan/emojilib/main/dist/emoji-en-US.json" | \
              jq -r 'to_entries | .[] | "\(.key) \(.value | join(" "))"' > "$CACHE_FILE"
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
          KEYBINDS="{}"

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
              -keybinds)
                KEYBINDS="$2"
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
          DMENU_KEYBINDS="$KEYBINDS" \
          "$QS_BIN" -p "$QML_FILE" 2>&1 | grep -E "QS_DMENU_(RESULT|KEYBIND|DROPDOWN):" | sed 's/^.*QS_DMENU_RESULT://; s/^.*QS_DMENU_KEYBIND:/KEYBIND:/; s/^.*QS_DMENU_DROPDOWN:/DROPDOWN:/'

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
      packages.qs-vpn = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "qs-vpn" ''
          # Quickshell VPN Selector - Multi-config with flag emojis
          # Opens qs-dmenu to select VPN from ~/Shared/VPNs/*.ovpn

          VPN_DIR="''${VPN_DIR:-$HOME/Shared/VPNs}"

          # Country code to flag emoji mapping (ISO 3166-1 alpha-2)
          declare -A FLAGS=(
            [al]="🇦🇱" [dz]="🇩🇿" [ad]="🇦🇩" [am]="🇦🇲" [bs]="🇧🇸" [bd]="🇧🇩"
            [us]="🇺🇸" [gb]="🇬🇧" [uk]="🇬🇧" [de]="🇩🇪" [fr]="🇫🇷" [nl]="🇳🇱" [ca]="🇨🇦"
            [au]="🇦🇺" [jp]="🇯🇵" [sg]="🇸🇬" [ch]="🇨🇭" [se]="🇸🇪" [no]="🇳🇴" [fi]="🇫🇮"
            [it]="🇮🇹" [es]="🇪🇸" [br]="🇧🇷" [mx]="🇲🇽" [in]="🇮🇳" [kr]="🇰🇷" [hk]="🇭🇰"
            [ie]="🇮🇪" [at]="🇦🇹" [be]="🇧🇪" [dk]="🇩🇰" [pl]="🇵🇱" [cz]="🇨🇿" [ro]="🇷🇴"
            [za]="🇿🇦" [nz]="🇳🇿" [ar]="🇦🇷" [cl]="🇨🇱" [co]="🇨🇴" [pt]="🇵🇹" [ru]="🇷🇺"
            [bg]="🇧🇬" [hr]="🇭🇷" [cy]="🇨🇾" [ee]="🇪🇪" [gr]="🇬🇷" [hu]="🇭🇺" [is]="🇮🇸"
            [lv]="🇱🇻" [lt]="🇱🇹" [lu]="🇱🇺" [mt]="🇲🇹" [md]="🇲🇩" [me]="🇲🇪" [mk]="🇲🇰"
            [rs]="🇷🇸" [sk]="🇸🇰" [si]="🇸🇮" [ua]="🇺🇦" [tr]="🇹🇷" [il]="🇮🇱" [ae]="🇦🇪"
            [th]="🇹🇭" [vn]="🇻🇳" [my]="🇲🇾" [ph]="🇵🇭" [id]="🇮🇩" [tw]="🇹🇼" [cn]="🇨🇳"
            [bo]="🇧🇴" [kh]="🇰🇭" [cr]="🇨🇷" [ec]="🇪🇨" [eg]="🇪🇬" [ge]="🇬🇪" [gl]="🇬🇱"
            [gt]="🇬🇹" [kz]="🇰🇿" [li]="🇱🇮" [mo]="🇲🇴" [mc]="🇲🇨" [mn]="🇲🇳" [ma]="🇲🇦"
            [np]="🇳🇵" [ng]="🇳🇬" [pa]="🇵🇦" [pe]="🇵🇪" [qa]="🇶🇦" [sa]="🇸🇦" [lk]="🇱🇰"
            [uy]="🇺🇾" [ve]="🇻🇪" [ba]="🇧🇦" [im]="🇮🇲"
          )

          declare -A COUNTRY_NAME_CODES=(
            [albania]="AL" [algeria]="DZ" [andorra]="AD" [argentina]="AR" [armenia]="AM"
            [australia]="AU" [austria]="AT" [bahamas]="BS" [bangladesh]="BD" [belgium]="BE"
            [bolivia]="BO" [bosnia_and_herzegovina]="BA" [brazil]="BR" [bulgaria]="BG"
            [cambodia]="KH" [chile]="CL" [china]="CN" [colombia]="CO" [costa_rica]="CR"
            [croatia]="HR" [cyprus]="CY" [czech_republic]="CZ" [ecuador]="EC" [egypt]="EG"
            [estonia]="EE" [france]="FR" [georgia]="GE" [greece]="GR" [greenland]="GL"
            [guatemala]="GT" [hong_kong]="HK" [hungary]="HU" [iceland]="IS" [india]="IN"
            [indonesia]="ID" [ireland]="IE" [isle_of_man]="IM" [israel]="IL" [kazakhstan]="KZ"
            [latvia]="LV" [liechtenstein]="LI" [lithuania]="LT" [luxembourg]="LU" [macao]="MO"
            [malaysia]="MY" [malta]="MT" [mexico]="MX" [moldova]="MD" [monaco]="MC"
            [mongolia]="MN" [montenegro]="ME" [morocco]="MA" [nepal]="NP" [netherlands]="NL"
            [new_zealand]="NZ" [nigeria]="NG" [north_macedonia]="MK" [norway]="NO" [panama]="PA"
            [peru]="PE" [philippines]="PH" [poland]="PL" [portugal]="PT" [qatar]="QA"
            [romania]="RO" [saudi_arabia]="SA" [serbia]="RS" [singapore]="SG" [slovakia]="SK"
            [slovenia]="SI" [south_africa]="ZA" [south_korea]="KR" [sri_lanka]="LK"
            [switzerland]="CH" [taiwan]="TW" [turkey]="TR" [ukraine]="UA"
            [united_arab_emirates]="AE" [uruguay]="UY" [venezuela]="VE" [vietnam]="VN"
          )

          trim_suffix_tokens() {
            local name="$1"
            name="''${name%_optimized}"
            name="''${name%_streaming}"
            name="''${name%_streaming_optimized}"
            echo "$name"
          }

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
            local normalized="''${basename//-/_}"
            normalized=$(trim_suffix_tokens "$normalized")
            
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
            if [[ "$normalized" =~ ^([a-zA-Z]{2})[_[:space:]] ]]; then
              echo "''${BASH_REMATCH[1]}"
              return
            fi
            
            # Pattern 4: Known codes as whole words only (word boundaries)
            local upper_name="''${normalized^^}"
            upper_name="''${upper_name//[-_]/ }"  # normalize separators to spaces
            for code in GB UK US CA AU NZ DE FR NL BE AT CH SE NO FI DK IE IT ES PT PL CZ RO BG HR HU GR SI SK LT LV EE LU MT IS UA RS ME MK MD CY TR RU JP KR SG HK TW CN TH VN MY PH ID IN IL AE BR MX AR CL CO ZA; do
              # Match as whole word: start/space before, space/end after
              if [[ " $upper_name " == *" $code "* ]]; then
                echo "$code"
                return
              fi
            done

            local lower_name="''${normalized,,}"
            if [[ -n "''${COUNTRY_NAME_CODES[$lower_name]:-}" ]]; then
              echo "''${COUNTRY_NAME_CODES[$lower_name]}"
              return
            fi
            
            # Fallback: first 2 chars
            echo "''${normalized:0:2}"
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

          create_nmcli_import_copy() {
            local source_file="$1"
            local temp_file
            temp_file=$(mktemp /tmp/qs-vpn-import-XXXXXX.ovpn)
            cp "$source_file" "$temp_file"

            python -c 'import pathlib, re, sys; path = pathlib.Path(sys.argv[1]); content = path.read_text(); content = re.sub(r"\n?<auth-user-pass>\r?\n[\s\S]*?\r?\n</auth-user-pass>[ \t]*\r?\n?", "\n", content); content = re.sub(r"^[ \t]*auth-user-pass(?:[ \t]+[^\r\n]+)?[ \t]*$", "auth-user-pass", content, flags=re.MULTILINE); path.write_text(content if content.endswith("\n") else content + "\n")' "$temp_file"

            printf '%s\n' "$temp_file"
          }

          extract_inline_credentials() {
            local source_file="$1"

            python -c 'import pathlib, re, sys; path = pathlib.Path(sys.argv[1]); content = path.read_text(); match = re.search(r"<auth-user-pass>\r?\n([^\r\n]+)\r?\n([^\r\n]+)\r?\n</auth-user-pass>", content); print(match.group(1)) if match else None; print(match.group(2)) if match else None' "$source_file"
          }

          # Get currently active VPN connection name (full name with spaces)
          get_active_vpn() {
            # Get VPN connections that are currently active - extract full NAME field
            nmcli -t -f NAME,TYPE connection show --active | grep ':vpn$' | cut -d: -f1 | head -1
          }

          # Import and configure VPN (overwrites existing config)
          import_vpn() {
            local ovpn_file="$1"
            local vpn_name="$2"
            local temp_ovpn_file=""
            local imported_name=""
            local auth_username=""
            local auth_password=""

            cleanup_import_copy() {
              if [ -n "$temp_ovpn_file" ] && [ -f "$temp_ovpn_file" ]; then
                rm -f "$temp_ovpn_file"
              fi
            }

            trap cleanup_import_copy RETURN

            # Delete existing config to ensure fresh import with latest .ovpn
            if vpn_exists "$vpn_name"; then
              nmcli connection delete "$vpn_name" 2>/dev/null || true
            fi
            
            notify-send "VPN" "Importing $vpn_name..."
            temp_ovpn_file=$(create_nmcli_import_copy "$ovpn_file")
            imported_name=$(basename "$temp_ovpn_file" .ovpn)

            mapfile -t AUTH_LINES < <(extract_inline_credentials "$ovpn_file")
            if [ ''${#AUTH_LINES[@]} -ge 2 ]; then
              auth_username="''${AUTH_LINES[0]}"
              auth_password="''${AUTH_LINES[1]}"
            fi

            if vpn_exists "$imported_name"; then
              nmcli connection delete "$imported_name" 2>/dev/null || true
            fi

            if nmcli connection import type openvpn file "$temp_ovpn_file"; then
              # Rename to friendly name and enable autoconnect for persistence
              nmcli connection modify "$imported_name" connection.id "$vpn_name" 2>/dev/null || true
              if [ -n "$auth_username" ] && [ -n "$auth_password" ]; then
                nmcli connection modify "$vpn_name" \
                  vpn.user-name "$auth_username" \
                  vpn.secrets "password=$auth_password" 2>/dev/null || true
              fi
              nmcli connection modify "$vpn_name" connection.autoconnect yes 2>/dev/null || true
              nmcli connection modify "$vpn_name" connection.autoconnect-retries 0 2>/dev/null || true
              notify-send "VPN" "$vpn_name imported successfully"
            else
              notify-send -u critical "VPN Error" "Failed to import $vpn_name"
              return 1
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

          # Disconnect from VPN and remove config from NetworkManager
          disconnect_vpn() {
            local vpn_name="$1"
            notify-send "VPN" "Disconnecting from $vpn_name..."
            if nmcli connection down "$vpn_name" 2>/dev/null; then
              # Clean up the connection from NetworkManager
              if nmcli connection delete "$vpn_name" 2>/dev/null; then
                notify-send "VPN" "Disconnected and removed $vpn_name"
              else
                notify-send "VPN" "Disconnected from $vpn_name (config retained)"
              fi
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

            # Show menu with keybind support
            SELECTION=$(echo -e "$MENU_ENTRIES" | qs-dmenu -p "VPN" -mesg "Alt+K: SOCKS5 | Alt+Shift+K: HTTP | Alt+U: User | Alt+P: Browser" -keybinds '{"alt+k":"copy-socks5","alt+shift+k":"copy-http","alt+u":"copy-username","alt+p":"launch-playwright"}')

            [ -z "$SELECTION" ] && exit 0

            # Handle keybind result (format: KEYBIND:key:action:selection)
            if [[ "$SELECTION" == KEYBIND:* ]]; then
              IFS=':' read -r _ key action selected_vpn <<< "$SELECTION"
              # Extract the VPN name from selection (strip flag emoji and checkmark)
              CLEAN_NAME=$(echo "$selected_vpn" | sed 's/^[^ ]* //' | sed 's/ ✓$//')
              # Remove all spaces from VPN name for slug (proxy system ignores spaces)
              SLUG_NAME=$(printf '%s' "$CLEAN_NAME" | tr -d ' ')
              
              case "$action" in
                copy-socks5)
                  PROXY_LINK="socks5://$SLUG_NAME@127.0.0.1:10800"
                  printf '%s' "$PROXY_LINK" | wl-copy --type text/plain
                  notify-send "VPN Proxy" "Copied SOCKS5: $PROXY_LINK\n\nVPN activates automatically on first use"
                  ;;
                copy-http)
                  PROXY_LINK="http://$SLUG_NAME:@127.0.0.1:10801"
                  printf '%s' "$PROXY_LINK" | wl-copy --type text/plain
                  notify-send "VPN Proxy" "Copied HTTP: $PROXY_LINK\n\nVPN activates automatically on first use"
                  ;;
                copy-username)
                  printf '%s' "$SLUG_NAME" | wl-copy --type text/plain
                  notify-send "VPN Proxy" "Copied Username: $SLUG_NAME"
                  ;;
                launch-playwright)
                  notify-send "VPN Proxy" "Launching Playwright with $SLUG_NAME proxy..."
                  playwright-stealth-browser "http://$SLUG_NAME:@127.0.0.1:10801" &
                  ;;
              esac
              exit 0
            fi

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
