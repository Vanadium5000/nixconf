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
    {
      packages.sound-change = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "sound-change" ''
          increments="5"
          smallIncrements="1"

          case "$1" in
            mute)
              ${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
              ;;
            up)
              increment=''${2:-$increments}
              ${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ ''${increment}%+
              ;;
            down)
              increment=''${2:-$increments}
              ${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ ''${increment}%-
              ;;
            set)
              volume=''${2:-100}
              ${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ ''${volume}%
              ;;
            *)
              echo "Usage: $0 {mute|up [increment]|down [increment]|set [volume]}"
              exit 1
              ;;
          esac
        '';
      };

      packages.sound-up = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "sound-up" ''
          exec ${self'.packages.sound-change}/bin/sound-change up 5
        '';
      };

      packages.sound-up-small = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "sound-up-small" ''
          exec ${self'.packages.sound-change}/bin/sound-change up 1
        '';
      };

      packages.sound-down = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "sound-down" ''
          exec ${self'.packages.sound-change}/bin/sound-change down 5
        '';
      };

      packages.sound-down-small = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "sound-down-small" ''
          exec ${self'.packages.sound-change}/bin/sound-change down 1
        '';
      };

      packages.sound-toggle = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "sound-toggle" ''
          exec ${self'.packages.sound-change}/bin/sound-change mute
        '';
      };

      packages.sound-set = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "sound-set" ''
          exec ${self'.packages.sound-change}/bin/sound-change set "$1"
        '';
      };

      packages.qs-tools = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "qs-tools" ''
          #!/usr/bin/env bash
          set -euo pipefail

          # Rofi menu options
          options=(
            "Toggle Crosshair"
            "Create Autoclicker"
            "Toggle Pause Autoclickers"
            "Stop All Autoclickers"
          )

          # Show menu
          choice=$(printf "%s\n" "''${options[@]}" | ${lib.getExe self'.packages.qs-dmenu} -p "Select Action")

          # Execute commands based on choice
          case "$choice" in
            "Toggle Crosshair")
              ${self'.packages.toggle-crosshair}/bin/toggle-crosshair
              ;;
            "Create Autoclicker")
              ${self'.packages.create-autoclicker}/bin/create-autoclicker
              ;;
            "Toggle Pause Autoclickers")
              ${self'.packages.toggle-pause-autoclickers}/bin/toggle-pause-autoclickers
              ;;
            "Stop All Autoclickers")
              ${self'.packages.stop-autoclickers}/bin/stop-autoclickers
              ;;
          esac
        '';
      };

      packages.qs-wallpaper = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package =
          let
            wallpaperSources = {
              "Nixy Wallpapers" = "${
                inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.nixy-wallpapers
              }/wallpapers/";
              "Nixos Artwork" = "${
                inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.nixos-wallpapers
              }/wallpapers/";
            };
          in
          pkgs.writeShellScriptBin "qs-wallpaper" ''
            # Nix magic
            result=$(echo "${
              builtins.concatStringsSep "\n" (builtins.attrNames wallpaperSources ++ [ "Choose a file..." ])
            }" | \
            ${lib.getExe self'.packages.qs-dmenu})

            echo $result

            declare -A wallpaperSources=(${
              builtins.concatStringsSep "\n" (
                map (x: ''["${x}"]="${wallpaperSources.${x}}"'') (builtins.attrNames wallpaperSources)
              )
            })

            if [[ $result == "Choose a file..." ]];then
              echo "Choosing a specific file"
              # TODO: Implement a Quickshell file picker or use zenity/kdialog?
              # Falling back to zenity for file picking since we removed rofi
              wallPath=$(zenity --file-selection --title="Select Wallpaper" --file-filter="Images | *.jpg *.jpeg *.png *.gif")

              if [ -z "$wallPath" ]; then exit 0; fi

              echo "$wallPath"
              hyprctl hyprpaper preload "$wallPath"
              hyprctl hyprpaper wallpaper ",$wallPath"

              # For rofi & hyprlock wallpaper
              cp -f "$wallPath" ~/wallpaper/.current_wallpaper
              exit 0
            fi

            echo "Getting wallDIR"

            wallDIR="''${wallpaperSources["$result"]}"
            echo $wallDIR

            ${self'.packages.qs-wallpaper-selector}/bin/qs-wallpaper-selector "$wallDIR"

            exit 0
          '';
        runtimeInputs = [ pkgs.zenity ];
      };

      packages.qs-wallpaper-selector = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "qs-wallpaper-selector" ''

          # WALLPAPERS PATH
          if [[ -n "$1" ]]; then
              wallDIR=$1
          else
              echo "Enter the dir path to the wallpapers"
              exit 1
          fi

          # Retrieve image files using null delimiter to handle spaces in filenames
          mapfile -d "" PICS < <(find "''${wallDIR}" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" \) -print0)

          RANDOM_PIC="''${PICS[$((RANDOM % ''${#PICS[@]}))]}"
          RANDOM_PIC_NAME=". random"

          # qs-dmenu command
          qs_command="${lib.getExe self'.packages.qs-dmenu} -p 'Select Wallpaper'"

          # Sorting Wallpapers
          menu() {
          	# Sort the PICS array
          	IFS=$'\n' sorted_options=($(sort <<<"''${PICS[*]}"))

          	# Place ". random" at the beginning with the random picture as an icon
            # qs-dmenu uses simple text for now, icon support via \0icon\x1f is basic
          	# printf "%s\x00icon\x1f%s\n" "$RANDOM_PIC_NAME" "$RANDOM_PIC"
            echo "$RANDOM_PIC_NAME"

          	for pic_path in "''${sorted_options[@]}"; do
          		pic_name=$(basename "$pic_path")

          		# Displaying .gif to indicate animated images
          		if [[ ! "$pic_name" =~ \.gif$ ]]; then
          			# printf "%s\x00icon\x1f%s\n" "$(echo "$pic_name" | cut -d. -f1)" "$pic_path"
                    echo "$pic_name" | cut -d. -f1
          		else
          			printf "%s\n" "$pic_name"
          		fi
          	done
          }

          # Choice of wallpapers
          main() {
          	choice=$(menu | $qs_command)

          	# Trim any potential whitespace or hidden characters
          	choice=$(echo "$choice" | xargs)
          	RANDOM_PIC_NAME=$(echo "$RANDOM_PIC_NAME" | xargs)

          	# No choice case
          	if [[ -z "$choice" ]]; then
          		echo "No choice selected. Exiting."
          		exit 0
          	fi

          	# Random choice case
          	if [[ "$choice" == "$RANDOM_PIC_NAME" ]]; then
          		result="$RANDOM_PIC"
          		return
          	fi

          	# Find the index of the selected file
          	pic_index=-1
          	for i in "''${!PICS[@]}"; do
          		filename=$(basename "''${PICS[$i]}")
          		if [[ "$filename" == "$choice"* ]]; then
          			pic_index=$i
          			break
          		fi
          	done

          	if [[ $pic_index -ne -1 ]]; then
          		result="''${PICS[''$pic_index]}"
          	else
          		echo "Image not found."
          		exit 1
          	fi
          }


          main

          echo "$result"
          hyprctl hyprpaper preload "$result"
          hyprctl hyprpaper wallpaper ",$result"
          cp -f "$result" ~/wallpaper/.current_wallpaper # For rofi wallpaper
        '';
      };

      packages.nixos-wallpapers = pkgs.stdenv.mkDerivation {
        name = "nixos-wallpapers";
        src = inputs.nixos-artwork;

        sparseCheckout = [
          "wallpapers"
        ];

        # Overwrite normal build phase
        buildPhase = ''
          runHook preBuild
          runHook postBuild
        '';

        installPhase = ''
          mkdir -p $out
          cp -r wallpapers $out/
        '';
      };

      packages.nixy-wallpapers = pkgs.stdenv.mkDerivation {
        name = "nixy-wallpapers";
        src = inputs.nixy-wallpapers;

        sparseCheckout = [
          "wallpapers"
        ];

        # Overwrite normal build phase
        buildPhase = ''
          runHook preBuild
          runHook postBuild
        '';

        installPhase = ''
          mkdir -p $out
          cp -r wallpapers $out/
        '';
      };

      packages.toggle-lid-inhibit = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "toggle-lid-inhibit" ''
          #!/usr/bin/env bash

          PID_FILE="$HOME/.local/share/lid-inhibit.pid"
          SYSTEMD_INHIBIT="${pkgs.systemd}/bin/systemd-inhibit"
          SLEEP="${pkgs.coreutils}/bin/sleep"
          NOTIFY_SEND="${pkgs.libnotify}/bin/notify-send"

          if [ -f "$PID_FILE" ]; then
              PID=$(cat "$PID_FILE")
              if kill -0 "$PID" 2>/dev/null; then
                  kill "$PID" 2>/dev/null || true
                  rm -f "$PID_FILE"
                  $NOTIFY_SEND "Lid Inhibit" "Suspend inhibitator on lid close disabled"
                  echo "Disabled suspend inhibitator on lid close"
              else
                  rm -f "$PID_FILE"
                  echo "Stale PID removed; run again to enable"
              fi
          else
              mkdir -p "$(dirname "$PID_FILE")"
              # Use exec to replace the shell process with systemd-inhibit
              (exec $SYSTEMD_INHIBIT --what=handle-lid-switch --who=waybar-lid --why="Lid close suspend inhibited" --mode=block $SLEEP infinity) &
              INHIBIT_PID=$!
              echo $INHIBIT_PID > "$PID_FILE"
              $NOTIFY_SEND "Lid Inhibit" "Suspend inhibitator on lid close enabled"
              echo "Enabled suspend inhibitator on lid close (PID: $INHIBIT_PID)"
          fi
        '';
      };

      packages.lid-status = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "lid-status" ''
          #!/usr/bin/env bash

          PID_FILE="$HOME/.local/share/lid-inhibit.pid"
          if [ -f "$PID_FILE" ]; then
              PID=$(cat "$PID_FILE")
              if kill -0 "$PID" 2>/dev/null; then
                  echo '{"text": "🔓", "class": "active"}'
              else
                  rm -f "$PID_FILE"
                  echo '{"text": "��", "class": "inactive"}'
              fi
          else
              echo '{"text": "🔒", "class": "inactive"}'
          fi
        '';
      };
      packages.monero-wallet = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "monero-wallet" ''
          #!/usr/bin/env bash

          # Default configuration - can be overridden with environment variables
          DAEMON_ADDRESS=''${MONERO_DAEMON_ADDRESS:-"https://xmr.cryptostorm.is:18081"}
          WALLET_FILE=''${MONERO_WALLET_FILE:-"$HOME/Documents/MainWallet"}
          PASSWORD_STORE_PATH=''${MONERO_PASSWORD_STORE_PATH:-"monero/main_password"}

          # Get password from pass
          if ! PASSWORD=$(${
            (pkgs.pass.withExtensions (exts: [ exts.pass-otp ]))
          }/bin/pass "$PASSWORD_STORE_PATH" 2>/dev/null); then
              echo "Error: Could not retrieve password from pass store at '$PASSWORD_STORE_PATH'"
              echo "Make sure the password store entry exists and is accessible"
              exit 1
          fi

          # Launch monero-wallet-cli with proper arguments
          exec ${pkgs.monero-cli}/bin/monero-wallet-cli \
              --daemon-address "$DAEMON_ADDRESS" \
              --password "$PASSWORD" \
              --wallet-file "$WALLET_FILE" \
              "$@"
        '';
      };

      packages.autoclicker-daemon = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "autoclicker-daemon" ''
          #!/usr/bin/env bash
          set -euo pipefail

          CONFIG_FILE="/dev/shm/autoclicker_config"
          PID_FILE="/dev/shm/autoclicker_daemon_pid"
          PAUSED_FILE="/dev/shm/autoclicker_paused"

          while true; do
            if [ -f "$PAUSED_FILE" ]; then
              sleep 0.1
              continue
            fi
            if [ -f "$CONFIG_FILE" ]; then
              mapfile -t points < "$CONFIG_FILE"
              num_points=''${#points[@]}
              if [ $num_points -gt 0 ]; then
                sleep_time=$(echo "scale=5; 0.05 / $num_points" | ${pkgs.bc}/bin/bc)
                for point in "''${points[@]}"; do
                  IFS=' ' read -r x y <<< "$point"
                  hyprctl dispatch movecursor "$x" "$y"
                  ${pkgs.wlrctl}/bin/wlrctl pointer click left
                  sleep "$sleep_time"
                done
              else
                sleep 0.1
              fi
            else
              sleep 0.1
            fi
          done
        '';
      };

      packages.create-autoclicker = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "create-autoclicker" ''
          #!/usr/bin/env bash
          set -euo pipefail

          CONFIG_FILE="/dev/shm/autoclicker_config"
          DAEMON_PID_FILE="/dev/shm/autoclicker_daemon_pid"

          # Select point with slurp
          point=$(${pkgs.slurp}/bin/slurp -p)
          IFS=',' read -r x y _ <<< "''${point// 1x1/}"

          # Append to config
          echo "$x $y" >> "$CONFIG_FILE"

          # Spawn red point overlay
          hyprctl dispatch exec "X=$x Y=$y COLOR=#ff0000 ${pkgs.quickshell}/bin/qs -p ${./quickshell/autoclicker.qml}"

          # Start daemon if not running
          if [ ! -f "$DAEMON_PID_FILE" ] || ! kill -0 "$(cat "$DAEMON_PID_FILE")" 2>/dev/null; then
            hyprctl dispatch exec "${self'.packages.autoclicker-daemon}/bin/autoclicker-daemon"
            # Wait a brief moment for the process to start
            sleep 0.1
            # Find the PID using pgrep (assuming the daemon process name is unique)
            DAEMON_PID=$(pgrep -f "autoclicker-daemon")
            echo "$DAEMON_PID" > "$DAEMON_PID_FILE"
          fi
        '';
      };

      packages.stop-autoclickers = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "stop-autoclickers" ''
          #!/usr/bin/env bash
          set -euo pipefail

          DAEMON_PID_FILE="/dev/shm/autoclicker_daemon_pid"
          CONFIG_FILE="/dev/shm/autoclicker_config"

          # Kill daemon
          if [ -f "$DAEMON_PID_FILE" ]; then
            kill "$(cat "$DAEMON_PID_FILE")" 2>/dev/null || true
            rm -f "$DAEMON_PID_FILE"
          fi

          # Remove config
          rm -f "$CONFIG_FILE"

          # Kill all overlays - repeat multiple times - can fail, so leave at end
          for i in {1..10}; do ${pkgs.quickshell}/bin/qs kill -p ${./quickshell/autoclicker.qml}; done
        '';
      };

      packages.toggle-pause-autoclickers = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "toggle-pause-autoclickers" ''
          #!/usr/bin/env bash
          set -euo pipefail

          PAUSED_FILE="/dev/shm/autoclicker_paused"

          if [ -f "$PAUSED_FILE" ]; then
            # Resume
            rm -f "$PAUSED_FILE"
            echo "Autoclickers resumed"
          else
            # Pause
            touch "$PAUSED_FILE"
            echo "Autoclickers paused"
          fi
        '';
      };

      legacyPackages.scripts = with self'.packages; [
        sound-change
        sound-up
        sound-up-small
        sound-down
        sound-down-small
        sound-toggle
        sound-set
        qs-tools
        qs-wallpaper
        qs-wallpaper-selector
        toggle-lid-inhibit
        lid-status
        monero-wallet
        autoclicker-daemon
        create-autoclicker
        stop-autoclickers
        toggle-pause-autoclickers
        toggle-crosshair
        rofi-passmenu
        rofi-checklist
        rofi-music-search
        btrfs-backup
        synced-lyrics
        markdown-lint-mcp
        dictation
        toggle-lyrics-overlay
      ];
    };
}
