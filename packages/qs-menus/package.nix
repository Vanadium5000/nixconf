{
  inputs,
  self,
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
      theme = self.themes.mainTheme;
      inherit (theme)
        colors
        palette
        glass
        settings
        ;
      qmlRgba = self.themes.toQmlRgba;
      # Helper to prepare QML files for the Nix store
      # Quickshell requires imports to be valid. We can't easily use absolute paths for imports
      # without file:// schema, and editing the source is messy.
      # Instead, we create a derivation that mimics the source structure:
      # $out/
      #   ├── script.qml
      #   ├── lib -> /nix/store/.../lib
      # This allows 'import "./lib"' in the QML to work natively.
      mkThemeQml = pkgs.writeText "nixconf-qs-theme.qml" ''
        pragma Singleton
        import QtQuick

        QtObject {
            readonly property QtObject colors: QtObject {
                readonly property color base00: "${colors.base00}"
                readonly property color base01: "${colors.base01}"
                readonly property color base02: "${colors.base02}"
                readonly property color base03: "${colors.base03}"
                readonly property color base04: "${colors.base04}"
                readonly property color base05: "${colors.base05}"
                readonly property color base06: "${colors.base06}"
                readonly property color base07: "${colors.base07}"
                readonly property color red: "${colors.base08}"
                readonly property color orange: "${colors.base09}"
                readonly property color yellow: "${colors.base0A}"
                readonly property color green: "${colors.base0B}"
                readonly property color cyan: "${colors.base0C}"
                readonly property color blue: "${colors.base0D}"
                readonly property color magenta: "${colors.base0E}"
                readonly property color darkGreen: "${colors.base0F}"
                readonly property color accent: "${palette.accent}"
                readonly property color accentAlt: "${palette.accentAlt}"
                readonly property color background: "${palette.background}"
                readonly property color backgroundAlt: "${palette.backgroundAlt}"
                readonly property color foreground: "${palette.foreground}"
                readonly property color foregroundAlt: "${palette.foregroundAlt}"
                readonly property color border: "${palette.border}"
                readonly property color borderInactive: "${palette.borderInactive}"
                readonly property color error: "${palette.error}"
                readonly property color success: "${palette.success}"
                readonly property color warning: "${palette.warning}"
            }

            readonly property QtObject glass: QtObject {
                readonly property color backgroundColor: ${qmlRgba glass.background settings.opacity}
                readonly property color backgroundSolid: "${glass.backgroundSolid}"
                readonly property color accentColor: "${glass.accent}"
                readonly property color accentColorAlt: "${glass.accentAlt}"
                readonly property color textPrimary: "${glass.textPrimary}"
                readonly property color textSecondary: "${glass.textSecondary}"
                readonly property color textTertiary: ${qmlRgba glass.textSecondary 0.3}
                readonly property color separator: "${glass.separator}"
                readonly property color separatorOpaque: "${glass.separatorOpaque}"
                readonly property real highlightOpacity: ${toString glass.highlightOpacity}
                readonly property color innerStrokeColor: Qt.rgba(1, 1, 1, ${toString glass.innerStrokeOpacity})
                readonly property real borderOpacity: ${toString glass.borderOpacity}
                readonly property int borderWidth: ${toString settings.border-size}
                readonly property real shadowOpacity: ${toString glass.shadowOpacity}
                readonly property real shadowRadius: ${toString glass.shadowRadius}
                readonly property real shadowOffsetY: ${toString glass.shadowOffsetY}
                readonly property real blurRadius: ${toString glass.blurRadius}
                readonly property int cornerRadius: ${toString glass.cornerRadius}
                readonly property int cornerRadiusSmall: ${toString glass.cornerRadiusSmall}
                readonly property int padding: ${toString glass.padding}
                readonly property int itemSpacing: ${toString glass.itemSpacing}
                readonly property string fontFamily: "${settings.font}"
                readonly property int fontSizeSmall: ${toString glass.fontSizeSmall}
                readonly property int fontSizeMedium: ${toString glass.fontSizeMedium}
                readonly property int fontSizeLarge: ${toString glass.fontSizeLarge}
                readonly property int fontSizeTitle: ${toString glass.fontSizeTitle}
                readonly property int animationDuration: ${toString glass.animationDuration}
                readonly property int animationDurationSlow: ${toString glass.animationDurationSlow}
            }

            readonly property color background: colors.background
            readonly property color backgroundAlt: colors.backgroundAlt
            readonly property color foreground: colors.foreground
            readonly property color foregroundAlt: colors.foregroundAlt
            readonly property color accent: colors.accent
            readonly property color accentAlt: colors.accentAlt
            readonly property color error: colors.error
            readonly property color success: colors.success
            readonly property string fontName: glass.fontFamily
            readonly property int fontSize: glass.fontSizeMedium
            readonly property int fontSizeSmall: glass.fontSizeSmall
            readonly property int fontSizeLarge: glass.fontSizeLarge
            readonly property int rounding: glass.cornerRadius
            readonly property int gapsIn: glass.itemSpacing
            readonly property int gapsOut: glass.padding

            function rgba(baseColor, alpha) {
                return Qt.rgba(baseColor.r, baseColor.g, baseColor.b, alpha)
            }
        }
      '';
      mkQml =
        name: src:
        let
          env = pkgs.runCommandLocal "qs-${name}" { } ''
            mkdir -p $out
            mkdir -p $out/lib
            ln -s ${mkThemeQml} $out/lib/Theme.qml
            ln -s ${./lib}/GlassPanel.qml $out/lib/GlassPanel.qml
            ln -s ${./lib}/GlassButton.qml $out/lib/GlassButton.qml
            ln -s ${./lib}/InstanceLock.qml $out/lib/InstanceLock.qml
            ln -s ${./lib}/qmldir $out/lib/qmldir
            cp ${src} $out/${name}
            cp ${./list_apps.ts} $out/list_apps.ts 2>/dev/null || true
          '';
        in
        "${env}/${name}";
    in
    {

      packages.toggle-lyrics-overlay = inputs.wrappers.lib.wrapPackage {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "toggle-lyrics-overlay" ''
          # Toggle QuickShell lyrics overlay

          QML_FILE="${mkQml "lyrics-overlay.qml" ./lyrics-overlay.qml}"
          QS_BIN="${pkgs.quickshell}/bin/qs"
          export QML2_IMPORT_PATH="${pkgs.qt6.qt5compat}/lib/qt-6/qml''${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}"
          OVERLAY_COMMAND_DEFAULT="${self'.packages.lyricsctl}/bin/lyricsctl current --json --lines 4 --length ''${LYRICS_LENGTH:-0}"

          case "''${1:-toggle}" in
            show)
              # Kill existing instance first
              "$QS_BIN" kill -p "$QML_FILE" 2>/dev/null || true
              # Launch with environment configuration
              OVERLAY_COMMAND="''${OVERLAY_COMMAND:-$OVERLAY_COMMAND_DEFAULT}" \
              LYRICS_LINES="''${LYRICS_LINES:-0}" \
              LYRICS_POSITION="''${LYRICS_POSITION:-bottom}" \
              LYRICS_FONT_SIZE="''${LYRICS_FONT_SIZE:-18}" \
              LYRICS_COLOR="''${LYRICS_COLOR:-#ffffff}" \
              LYRICS_OPACITY="''${LYRICS_OPACITY:-0.82}" \
              LYRICS_SHADOW="''${LYRICS_SHADOW:-true}" \
              LYRICS_UPDATE_INTERVAL="''${LYRICS_UPDATE_INTERVAL:-400}" \
              LYRICS_SPACING="''${LYRICS_SPACING:-4}" \
              LYRICS_LENGTH="''${LYRICS_LENGTH:-0}" \
              "$QS_BIN" -p "$QML_FILE" &
              ;;
            hide)
              "$QS_BIN" kill -p "$QML_FILE"
              ;;
            *)  # toggle
              if ! "$QS_BIN" kill -p "$QML_FILE" 2>/dev/null; then
                OVERLAY_COMMAND="''${OVERLAY_COMMAND:-$OVERLAY_COMMAND_DEFAULT}" \
                LYRICS_LINES="''${LYRICS_LINES:-0}" \
                LYRICS_POSITION="''${LYRICS_POSITION:-bottom}" \
                LYRICS_FONT_SIZE="''${LYRICS_FONT_SIZE:-18}" \
                LYRICS_COLOR="''${LYRICS_COLOR:-#ffffff}" \
                LYRICS_OPACITY="''${LYRICS_OPACITY:-0.82}" \
                LYRICS_SHADOW="''${LYRICS_SHADOW:-true}" \
                LYRICS_UPDATE_INTERVAL="''${LYRICS_UPDATE_INTERVAL:-400}" \
                LYRICS_SPACING="''${LYRICS_SPACING:-4}" \
                LYRICS_LENGTH="''${LYRICS_LENGTH:-0}" \
                "$QS_BIN" -p "$QML_FILE" &
              fi
              ;;
          esac
        '';

        runtimePkgs = [
          pkgs.quickshell
        ];
      };

      packages.qs-emoji = inputs.wrappers.lib.wrapPackage {
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
        runtimePkgs = [
          self'.packages.qs-dmenu
          pkgs.curl
          pkgs.jq
          pkgs.wl-clipboard
          pkgs.libnotify
          pkgs.coreutils
        ];
      };

      packages.qs-nerd = inputs.wrappers.lib.wrapPackage {
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
        runtimePkgs = [
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

      packages.qs-dmenu = inputs.wrappers.lib.wrapPackage {
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
          #   -no-select             Start with no selected item
          #   -input TEXT            Initial input/filter text
          #   -mark-input            Prefix custom input output with INPUT:
          #   -placeholder TEXT      Placeholder text for input
          #   -filter MODE           Filter mode: fuzzy, prefix, exact (default: fuzzy)
          #   -multi-select          Enter toggles items; Shift+Enter outputs only toggled items
          #   -dmenu                 Ignored (compatibility)

          PROMPT="Select"
          LINES=15
          PASSWORD="false"
          CASE_INSENSITIVE="true"
          SELECTED=0
          INITIAL_INPUT=""
          MARK_INPUT="false"
          PLACEHOLDER=""
          FILTER="fuzzy"
          MESSAGE=""
          KEYBINDS="{}"
          MULTI_SELECT="false"

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
              -no-select|-no-selected)
                SELECTED="-1"
                shift
                ;;
              -input)
                INITIAL_INPUT="$2"
                shift 2
                ;;
              -mark-input)
                MARK_INPUT="true"
                shift
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
              -multi-select|-multi)
                MULTI_SELECT="true"
                shift
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

          # Save stdin and return value through files: Quickshell writes logs to stdout
          # in some launch contexts, so stdout parsing is not a reliable IPC channel.
          INPUT_FILE=$(mktemp)
          OUTPUT_FILE=$(mktemp)
          LOG_FILE=$(mktemp)
          : > "$OUTPUT_FILE"
          trap 'rm -f "$INPUT_FILE" "$OUTPUT_FILE" "$LOG_FILE"' EXIT
          cat > "$INPUT_FILE"

          QML_FILE="${mkQml "dmenu.qml" ./dmenu.qml}"
          QS_BIN="${pkgs.quickshell}/bin/qs"
          export QML2_IMPORT_PATH="${pkgs.qt6.qt5compat}/lib/qt-6/qml''${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}"

          # Run Quickshell and print only the explicit selection written by QML.
          DMENU_INPUT_FILE="$INPUT_FILE" \
            DMENU_OUTPUT_FILE="$OUTPUT_FILE" \
            DMENU_PROMPT="$PROMPT" \
            DMENU_LINES="$LINES" \
            DMENU_PASSWORD="$PASSWORD" \
            DMENU_CASE_INSENSITIVE="$CASE_INSENSITIVE" \
            DMENU_SELECTED="$SELECTED" \
            DMENU_INITIAL_INPUT="$INITIAL_INPUT" \
            DMENU_MARK_INPUT="$MARK_INPUT" \
            DMENU_PLACEHOLDER="$PLACEHOLDER" \
            DMENU_FILTER="$FILTER" \
            DMENU_MESSAGE="$MESSAGE" \
            DMENU_KEYBINDS="$KEYBINDS" \
            DMENU_MULTI_SELECT="$MULTI_SELECT" \
            "$QS_BIN" -p "$QML_FILE" >"$LOG_FILE" 2>&1
          QS_STATUS=$?
          if [ "$QS_STATUS" -ne 0 ]; then
            exit "$QS_STATUS"
          fi

          if [ -s "$OUTPUT_FILE" ]; then
            cat "$OUTPUT_FILE"
            printf '\n'
          fi

          # Cleanup is handled by the EXIT trap.
        '';
        runtimePkgs = [
          pkgs.quickshell
          pkgs.coreutils
        ];
      };

      packages.qs-askpass = inputs.wrappers.lib.wrapPackage {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "qs-askpass" ''
          # Quickshell askpass (password prompt)
          # Usage: qs-askpass "Prompt"

          PROMPT="''${1:-Password:}"

          # We feed empty input to dmenu but enable password mode
          echo "" | ${lib.getExe self'.packages.qs-dmenu} -p "$PROMPT" -password
        '';
        runtimePkgs = [ self'.packages.qs-dmenu ];
      };
      packages.qs-vpn = inputs.wrappers.lib.wrapPackage {
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

                      # NM openvpn cannot store inline <auth-user-pass> blocks; flatten to bare
                      # auth-user-pass and inject credentials via vpn.user-name / vpn.secrets after import.
                      # Also drop IPv6 route pull so PIA/AirVPN cannot install 2000::/3 without a global
                      # IPv6 address (Happy Eyeballs then blackholes dual-stack sites onto loopback/nginx).
                      # Source: NetworkManager-openvpn password import + OpenVPN pull-filter.
                      python -c 'import pathlib, re, sys
          path = pathlib.Path(sys.argv[1])
          content = path.read_text()
          content = re.sub(r"\n?<auth-user-pass>\r?\n[\s\S]*?\r?\n</auth-user-pass>[ \t]*\r?\n?", "\nauth-user-pass\n", content)
          content = re.sub(r"^[ \t]*auth-user-pass(?:[ \t]+[^\r\n]+)?[ \t]*$", "auth-user-pass", content, flags=re.MULTILINE)
          if "auth-user-pass" not in content:
              content += "\nauth-user-pass\n"
          for line in (
              "pull-filter ignore \"redirect-gateway ipv6\"",
              "pull-filter ignore \"route-ipv6\"",
              "pull-filter ignore \"ifconfig-ipv6\"",
              "pull-filter ignore \"dhcp-option DNS\"",
              "pull-filter ignore \"dhcp-option DNS6\"",
              "pull-filter ignore \"dhcp-option DOMAIN\"",
              "pull-filter ignore \"dhcp-option DOMAIN-SEARCH\"",
          ):
              if line not in content:
                  content = content.rstrip() + "\n" + line + "\n"
          path.write_text(content if content.endswith("\n") else content + "\n")
          ' "$temp_file"

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
                        # Rename to friendly name; never leave password-flags=agent-owned only
                        # (password-flags=1) after import — that yields AUTH_FAILED with no askpass.
                        nmcli connection modify "$imported_name" connection.id "$vpn_name" 2>/dev/null || true
                        if [ -n "$auth_username" ] && [ -n "$auth_password" ]; then
                          nmcli connection modify "$vpn_name" \
                            vpn.user-name "$auth_username" \
                            +vpn.data password-flags=0 \
                            vpn.secrets "password=$auth_password" \
                            2>/dev/null || true
                          # Ensure secrets are stored in the keyfile connection, not only session agent.
                          nmcli connection modify "$vpn_name" \
                            vpn.secrets "password=$auth_password" \
                            2>/dev/null || true
                        fi
                        # Prefer not to autostart imported VPNs. Leave DNS alone so
                        # captive portals and tunnel DNS still work when needed; global
                        # Cloudflare/DoT preference lives in networking.nix.
                        # Disable IPv6 on the tunnel profile to avoid Happy-Eyeballs stalls.
                        nmcli connection modify "$vpn_name" \
                          ipv6.method disabled \
                          connection.autoconnect no \
                          connection.autoconnect-retries 0 \
                          2>/dev/null || true
                        notify-send "VPN" "$vpn_name imported successfully"
                      else
                        notify-send -u critical "VPN Error" "Failed to import $vpn_name"
                        return 1
                      fi
                    }

                    # Connect to VPN
                    connect_vpn() {
                      local vpn_name="$1"
                      local out
                      notify-send "VPN" "Connecting to $vpn_name..."
                      if out=$(nmcli connection up "$vpn_name" 2>&1); then
                        # Drop residual IPv6 full-tunnel blackholes from plain openvpn runs.
                        # Root NM dispatcher vpn-drop-broken-ipv6 also handles this.
                        ip -6 route del 2000::/3 dev tun0 2>/dev/null || true
                        ip -6 route show | grep -E 'dev tun' | while read -r line; do
                          case "$line" in
                            fe80:*|ff00:*|local*|multicast*) ;;
                            *) ip -6 route del $line 2>/dev/null || true ;;
                          esac
                        done
                        notify-send "VPN" "Connected to $vpn_name"
                      else
                        notify-send -u critical "VPN Error" "Failed to connect to $vpn_name\n$out"
                        return 1
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
        runtimePkgs = [
          pkgs.networkmanager
          pkgs.libnotify
          pkgs.gnugrep
          pkgs.coreutils
          pkgs.findutils
          pkgs.gawk
          pkgs.iproute2
          pkgs.python3
          self'.packages.qs-dmenu
        ];
      };

      packages.qs-menus = pkgs.symlinkJoin {
        name = "qs-menus";
        paths = [
          self'.packages.qs-askpass
          self'.packages.qs-dmenu
          self'.packages.qs-emoji
          self'.packages.qs-nerd
          self'.packages.qs-vpn
          self'.packages.toggle-lyrics-overlay
        ];
        meta = {
          description = "Quickshell menu and launcher wrappers from this flake";
          mainProgram = "qs-dmenu";
          platforms = pkgs.lib.platforms.linux;
        };
      };
    };
}
