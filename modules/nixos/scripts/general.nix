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

          # QS menu options
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

              # For qs-dmenu & hyprlock wallpaper
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
          qs_command=(env DMENU_VIEW=grid DMENU_GRID_COLS=3 DMENU_ICON_SIZE=256 ${lib.getExe self'.packages.qs-dmenu} -p "Select Wallpaper")

          # Sorting Wallpapers
          menu() {
          	# Sort the PICS array
          	IFS=$'\n' sorted_options=($(sort <<<"''${PICS[*]}"))

          	# Place ". random" at the beginning with the random picture as an icon
          	printf "%s\x00icon\x1f%s\n" "$RANDOM_PIC_NAME" "$RANDOM_PIC" || true

          	for pic_path in "''${sorted_options[@]}"; do
          		pic_name=$(basename "$pic_path")

          		# Displaying .gif to indicate animated images
          		if [[ ! "$pic_name" =~ \.gif$ ]]; then
          			printf "%s\x00icon\x1f%s\n" "$(echo "$pic_name" | cut -d. -f1)" "$pic_path" || true
          		else
          			printf "%s\x00icon\x1f%s\n" "$pic_name" "$pic_path" || true
          		fi
          	done
          }

          # Choice of wallpapers
          main() {
          	choice=$(menu | "''${qs_command[@]}")

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
        package =
          let
            passCmd = "${(pkgs.pass.withExtensions (exts: [ exts.pass-otp ]))}/bin/pass";
          in
          pkgs.writeShellScriptBin "monero-wallet" ''
            #!/usr/bin/env bash
            set -euo pipefail

            # Configuration with WALLET env variable support
            WALLET_NAME="''${WALLET:-main_wallet}"
            DAEMON_ADDRESS="''${MONERO_DAEMON_ADDRESS:-https://xmr.cryptostorm.is:18081}"
            WALLET_DIR="''${MONERO_WALLET_DIR:-$HOME/Shared/Coins/monero}"
            WALLET_FILE="''${MONERO_WALLET_FILE:-$WALLET_DIR/$WALLET_NAME}"
            PASSWORD_STORE_PATH="''${MONERO_PASSWORD_STORE_PATH:-monero/$WALLET_NAME}"

            # Validate wallet name (alphanumeric, underscore, hyphen only)
            if [[ ! "$WALLET_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
                echo "Error: Invalid wallet name '$WALLET_NAME'"
                echo "Wallet name must contain only alphanumeric characters, underscores, and hyphens"
                exit 1
            fi

            # Check if wallet file exists
            if [[ ! -f "$WALLET_FILE" ]]; then
                echo "Warning: Wallet file does not exist: $WALLET_FILE"
                echo ""
                echo "To initialize a new wallet, a pass entry for the wallet password is required."
                echo "If it doesn't exist, create it first with:"
                echo "   pass insert $PASSWORD_STORE_PATH"
                echo ""
                read -rp "Would you like to proceed with wallet initialization? [y/N]: " response
                case "$response" in
                    [yY][eE][sS]|[yY])
                        # Check if pass entry exists before proceeding
                        if ! ${passCmd} show "$PASSWORD_STORE_PATH" &>/dev/null; then
                            echo ""
                            echo "Error: Password store entry '$PASSWORD_STORE_PATH' does not exist."
                            echo "Please create it first with: pass insert $PASSWORD_STORE_PATH"
                            exit 1
                        fi
                        PASSWORD=$(${passCmd} show "$PASSWORD_STORE_PATH")

                        # Create wallet directory if it doesn't exist
                        if [[ ! -d "$WALLET_DIR" ]]; then
                            echo "Creating wallet directory: $WALLET_DIR"
                            mkdir -p "$WALLET_DIR"
                        fi

                        echo "Initializing new wallet..."
                        exec ${pkgs.monero-cli}/bin/monero-wallet-cli \
                            --generate-new-wallet "$WALLET_FILE" \
                            --daemon-address "$DAEMON_ADDRESS" \
                            --password "$PASSWORD" \
                            "$@"
                        ;;
                    *)
                        echo "Aborted."
                        exit 0
                        ;;
                esac
            fi

            # Verify wallet file is readable
            if [[ ! -r "$WALLET_FILE" ]]; then
                echo "Error: Wallet file is not readable: $WALLET_FILE"
                echo "Check file permissions"
                exit 1
            fi

            # Check if pass entry exists
            if ! ${passCmd} show "$PASSWORD_STORE_PATH" &>/dev/null; then
                echo "Error: Could not retrieve password from pass store at '$PASSWORD_STORE_PATH'"
                echo "Make sure the password store entry exists and is accessible"
                echo ""
                echo "To create the entry, run: pass insert $PASSWORD_STORE_PATH"
                exit 1
            fi

            # Get password from pass (already verified it exists above)
            PASSWORD=$(${passCmd} show "$PASSWORD_STORE_PATH")

            # Validate password is not empty
            if [[ -z "$PASSWORD" ]]; then
                echo "Error: Password retrieved from pass store is empty"
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

      packages.bitcoin-wallet = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package =
          let
            passCmd = "${(pkgs.pass.withExtensions (exts: [ exts.pass-otp ]))}/bin/pass";
          in
          pkgs.writeShellScriptBin "bitcoin-wallet" ''
            #!/usr/bin/env bash
            set -euo pipefail

            # Configuration with WALLET env variable support
            WALLET_NAME="''${WALLET:-main_wallet}"
            ELECTRUM_DIR="''${ELECTRUM_DIR:-$HOME/Shared/Coins/bitcoin}"
            WALLET_FILE="''${ELECTRUM_WALLET_FILE:-$ELECTRUM_DIR/wallets/$WALLET_NAME}"
            PASSWORD_STORE_PATH="''${ELECTRUM_PASSWORD_STORE_PATH:-bitcoin/$WALLET_NAME}"

            # Validate wallet name (alphanumeric, underscore, hyphen only)
            if [[ ! "$WALLET_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
                echo "Error: Invalid wallet name '$WALLET_NAME'"
                echo "Wallet name must contain only alphanumeric characters, underscores, and hyphens"
                exit 1
            fi

            # Check if wallet file exists
            WALLET_DIR="$(dirname "$WALLET_FILE")"
            if [[ ! -f "$WALLET_FILE" ]]; then
                echo "Warning: Wallet file does not exist: $WALLET_FILE"
                echo ""
                echo "To initialize a new wallet, a pass entry for the wallet password is required."
                echo "If it doesn't exist, create it first with:"
                echo "   pass insert $PASSWORD_STORE_PATH"
                echo ""
                read -rp "Would you like to proceed with wallet initialization? [y/N]: " response
                case "$response" in
                    [yY][eE][sS]|[yY])
                        # Check if pass entry exists before proceeding
                        if ! ${passCmd} show "$PASSWORD_STORE_PATH" &>/dev/null; then
                            echo ""
                            echo "Error: Password store entry '$PASSWORD_STORE_PATH' does not exist."
                            echo "Please create it first with: pass insert $PASSWORD_STORE_PATH"
                            exit 1
                        fi
                        PASSWORD=$(${passCmd} show "$PASSWORD_STORE_PATH")

                        # Create wallet directory if it doesn't exist
                        if [[ ! -d "$WALLET_DIR" ]]; then
                            echo "Creating wallet directory: $WALLET_DIR"
                            mkdir -p "$WALLET_DIR"
                        fi

                        echo "Creating new wallet..."
                        # Create wallet with electrum (password set during creation)
                        ${pkgs.electrum}/bin/electrum --offline create --wallet "$WALLET_FILE" --password "$PASSWORD"
                        echo ""
                        echo "Wallet created successfully at: $WALLET_FILE"
                        echo "IMPORTANT: Please back up your seed phrase!"
                        echo "Run: electrum --offline --wallet '$WALLET_FILE' getseed --password '\$PASSWORD'"
                        echo "(where \$PASSWORD is your wallet password from pass)"
                        echo ""
                        echo "Starting wallet GUI..."
                        exec ${pkgs.electrum}/bin/electrum --wallet "$WALLET_FILE" "$@"
                        ;;
                    *)
                        echo "Aborted."
                        exit 0
                        ;;
                esac
            fi

            # Verify wallet file is readable
            if [[ ! -r "$WALLET_FILE" ]]; then
                echo "Error: Wallet file is not readable: $WALLET_FILE"
                echo "Check file permissions"
                exit 1
            fi

            # Check if pass entry exists
            if ! ${passCmd} show "$PASSWORD_STORE_PATH" &>/dev/null; then
                echo "Error: Could not retrieve password from pass store at '$PASSWORD_STORE_PATH'"
                echo "Make sure the password store entry exists and is accessible"
                echo ""
                echo "To create the entry, run: pass insert $PASSWORD_STORE_PATH"
                exit 1
            fi

            # Password verified to exist - electrum GUI will prompt for it interactively
            # We verify pass entry exists so user knows their password is available
            echo "Wallet password available in pass at: $PASSWORD_STORE_PATH"
            echo "Electrum will prompt for the password in the GUI."
            echo ""

            # Launch electrum GUI with wallet
            exec ${pkgs.electrum}/bin/electrum --wallet "$WALLET_FILE" "$@"
          '';
      };

      packages.dogecoin-wallet = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package =
          let
            passCmd = "${(pkgs.pass.withExtensions (exts: [ exts.pass-otp ]))}/bin/pass";
            dogecoinPkg = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.dogecoin;
          in
          pkgs.writeShellScriptBin "dogecoin-wallet" ''
            #!/usr/bin/env bash
            set -euo pipefail

            # Configuration with WALLET env variable support
            WALLET_NAME="''${WALLET:-main_wallet}"
            DOGECOIN_DIR="''${DOGECOIN_DIR:-$HOME/Shared/Coins/dogecoin}"
            WALLET_FILE="''${DOGECOIN_WALLET_FILE:-$DOGECOIN_DIR/$WALLET_NAME.dat}"
            PASSWORD_STORE_PATH="''${DOGECOIN_PASSWORD_STORE_PATH:-dogecoin/$WALLET_NAME}"

            # Validate wallet name (alphanumeric, underscore, hyphen only)
            if [[ ! "$WALLET_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
                echo "Error: Invalid wallet name '$WALLET_NAME'"
                echo "Wallet name must contain only alphanumeric characters, underscores, and hyphens"
                exit 1
            fi

            # Check if wallet file exists
            if [[ ! -f "$WALLET_FILE" ]]; then
                echo "Warning: Wallet file does not exist: $WALLET_FILE"
                echo ""
                echo "To initialize a new wallet, a pass entry for the wallet password is required."
                echo "If it doesn't exist, create it first with:"
                echo "   pass insert $PASSWORD_STORE_PATH"
                echo ""
                read -rp "Would you like to proceed with wallet initialization? [y/N]: " response
                case "$response" in
                    [yY][eE][sS]|[yY])
                        # Check if pass entry exists before proceeding
                        if ! ${passCmd} show "$PASSWORD_STORE_PATH" &>/dev/null; then
                            echo ""
                            echo "Error: Password store entry '$PASSWORD_STORE_PATH' does not exist."
                            echo "Please create it first with: pass insert $PASSWORD_STORE_PATH"
                            exit 1
                        fi
                        PASSWORD=$(${passCmd} show "$PASSWORD_STORE_PATH")

                        # Create wallet directory if it doesn't exist
                        if [[ ! -d "$DOGECOIN_DIR" ]]; then
                            echo "Creating wallet directory: $DOGECOIN_DIR"
                            mkdir -p "$DOGECOIN_DIR"
                        fi

                        echo "Initializing new Dogecoin wallet..."
                        echo "Starting dogecoind with wallet encryption..."

                        # Create a temporary config for initialization
                        TEMP_CONF=$(mktemp)
                        cat > "$TEMP_CONF" <<CONF
            datadir=$DOGECOIN_DIR
            wallet=$WALLET_NAME
            server=0
            listen=0
            CONF

                        # Start daemon briefly to create wallet, then encrypt it
                        ${dogecoinPkg}/bin/dogecoind -conf="$TEMP_CONF" -daemon
                        sleep 3

                        # Encrypt the wallet with the password
                        ${dogecoinPkg}/bin/dogecoin-cli -conf="$TEMP_CONF" encryptwallet "$PASSWORD" || true
                        sleep 2

                        # Stop the daemon (encryptwallet auto-stops it, but just in case)
                        ${dogecoinPkg}/bin/dogecoin-cli -conf="$TEMP_CONF" stop 2>/dev/null || true
                        rm -f "$TEMP_CONF"

                        echo ""
                        echo "Wallet created successfully at: $DOGECOIN_DIR"
                        echo "IMPORTANT: Back up your wallet.dat file!"
                        echo ""
                        echo "To get a new receiving address, run:"
                        echo "   dogecoin-wallet getnewaddress"
                        exit 0
                        ;;
                    *)
                        echo "Aborted."
                        exit 0
                        ;;
                esac
            fi

            # Verify wallet directory is readable
            if [[ ! -r "$DOGECOIN_DIR" ]]; then
                echo "Error: Wallet directory is not readable: $DOGECOIN_DIR"
                echo "Check file permissions"
                exit 1
            fi

            # Check if pass entry exists
            if ! ${passCmd} show "$PASSWORD_STORE_PATH" &>/dev/null; then
                echo "Error: Could not retrieve password from pass store at '$PASSWORD_STORE_PATH'"
                echo "Make sure the password store entry exists and is accessible"
                echo ""
                echo "To create the entry, run: pass insert $PASSWORD_STORE_PATH"
                exit 1
            fi

            # Get password from pass
            PASSWORD=$(${passCmd} show "$PASSWORD_STORE_PATH")

            # Validate password is not empty
            if [[ -z "$PASSWORD" ]]; then
                echo "Error: Password retrieved from pass store is empty"
                exit 1
            fi

            # Create config file for this session
            CONF_FILE="$DOGECOIN_DIR/dogecoin.conf"
            if [[ ! -f "$CONF_FILE" ]]; then
                cat > "$CONF_FILE" <<CONF
            datadir=$DOGECOIN_DIR
            wallet=$WALLET_NAME
            server=1
            rpcuser=dogecoin
            rpcpassword=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9')
            CONF
                chmod 600 "$CONF_FILE"
            fi

            # If no arguments, show wallet info
            if [[ $# -eq 0 ]]; then
                echo "Dogecoin Wallet: $WALLET_NAME"
                echo "Data directory: $DOGECOIN_DIR"
                echo ""
                echo "Starting daemon if not running..."

                # Check if daemon is running
                if ! ${dogecoinPkg}/bin/dogecoin-cli -datadir="$DOGECOIN_DIR" getblockchaininfo &>/dev/null; then
                    ${dogecoinPkg}/bin/dogecoind -datadir="$DOGECOIN_DIR" -daemon
                    sleep 3
                fi

                # Unlock wallet for operations
                ${dogecoinPkg}/bin/dogecoin-cli -datadir="$DOGECOIN_DIR" walletpassphrase "$PASSWORD" 60 2>/dev/null || true

                echo "Balance:"
                ${dogecoinPkg}/bin/dogecoin-cli -datadir="$DOGECOIN_DIR" getbalance
                echo ""
                echo "Run 'dogecoin-wallet help' for available commands"
                exit 0
            fi

            # Handle help
            if [[ "$1" == "--help" || "$1" == "-h" ]]; then
                echo "dogecoin-wallet - Dogecoin Core wallet wrapper"
                echo ""
                echo "USAGE:"
                echo "  dogecoin-wallet [COMMAND] [ARGS...]"
                echo ""
                echo "ENVIRONMENT VARIABLES:"
                echo "  WALLET                     Wallet name (default: main_wallet)"
                echo "  DOGECOIN_DIR               Data directory (default: ~/Shared/Coins/dogecoin)"
                echo "  DOGECOIN_PASSWORD_STORE_PATH  Pass entry path (default: dogecoin/\$WALLET)"
                echo ""
                echo "EXAMPLES:"
                echo "  dogecoin-wallet                    # Show balance"
                echo "  dogecoin-wallet getnewaddress      # Get new receiving address"
                echo "  dogecoin-wallet sendtoaddress <addr> <amount>  # Send DOGE"
                echo "  dogecoin-wallet listtransactions   # List recent transactions"
                echo "  WALLET=savings dogecoin-wallet     # Use different wallet"
                echo ""
                echo "DOGECOIN-CLI COMMANDS:"
                ${dogecoinPkg}/bin/dogecoin-cli --help
                exit 0
            fi

            # Ensure daemon is running
            if ! ${dogecoinPkg}/bin/dogecoin-cli -datadir="$DOGECOIN_DIR" getblockchaininfo &>/dev/null; then
                echo "Starting dogecoind..."
                ${dogecoinPkg}/bin/dogecoind -datadir="$DOGECOIN_DIR" -daemon
                sleep 3
            fi

            # Unlock wallet for 60 seconds for any operation that needs it
            ${dogecoinPkg}/bin/dogecoin-cli -datadir="$DOGECOIN_DIR" walletpassphrase "$PASSWORD" 60 2>/dev/null || true

            # Pass through to dogecoin-cli
            exec ${dogecoinPkg}/bin/dogecoin-cli -datadir="$DOGECOIN_DIR" "$@"
          '';
      };

      packages.ethereum-wallet = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package =
          let
            passCmd = "${(pkgs.pass.withExtensions (exts: [ exts.pass-otp ]))}/bin/pass";
            castCmd = "${pkgs.foundry}/bin/cast";
          in
          pkgs.writeShellScriptBin "ethereum-wallet" ''
            #!/usr/bin/env bash
            set -euo pipefail

            # Configuration with environment variable support
            WALLET_NAME="''${WALLET:-main_wallet}"
            ETH_WALLET_DIR="''${ETH_WALLET_DIR:-$HOME/Shared/Coins/ethereum}"
            ETH_WALLET_FILE="''${ETH_WALLET_FILE:-$ETH_WALLET_DIR/$WALLET_NAME}"
            PASSWORD_STORE_PATH="''${ETH_PASSWORD_STORE_PATH:-ethereum/$WALLET_NAME}"
            RPC_URL="''${ETH_RPC_URL:-https://eth.llamarpc.com}"

            # Export RPC URL for cast commands
            export ETH_RPC_URL="$RPC_URL"

            # Validate wallet name (alphanumeric, underscore, hyphen only)
            if [[ ! "$WALLET_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
                echo "Error: Invalid wallet name '$WALLET_NAME'"
                echo "Wallet name must contain only alphanumeric characters, underscores, and hyphens"
                exit 1
            fi

            # Check if wallet file exists
            if [[ ! -f "$ETH_WALLET_FILE" ]]; then
                echo "Warning: Wallet file does not exist: $ETH_WALLET_FILE"
                echo ""
                echo "To initialize a new wallet, a pass entry for the wallet password is required."
                echo "If it doesn't exist, create it first with:"
                echo "   pass insert $PASSWORD_STORE_PATH"
                echo ""
                read -rp "Would you like to proceed with wallet initialization? [y/N]: " response
                case "$response" in
                    [yY][eE][sS]|[yY])
                        # Check if pass entry exists before proceeding
                        if ! ${passCmd} show "$PASSWORD_STORE_PATH" &>/dev/null; then
                            echo ""
                            echo "Error: Password store entry '$PASSWORD_STORE_PATH' does not exist."
                            echo "Please create it first with: pass insert $PASSWORD_STORE_PATH"
                            exit 1
                        fi
                        PASSWORD=$(${passCmd} show "$PASSWORD_STORE_PATH")

                        # Validate password is not empty
                        if [[ -z "$PASSWORD" ]]; then
                            echo "Error: Password retrieved from pass store is empty"
                            exit 1
                        fi

                        # Create wallet directory if it doesn't exist
                        if [[ ! -d "$ETH_WALLET_DIR" ]]; then
                            echo "Creating wallet directory: $ETH_WALLET_DIR"
                            mkdir -p "$ETH_WALLET_DIR"
                        fi

                        echo "Initializing new Ethereum wallet..."
                        ${castCmd} wallet new "$ETH_WALLET_DIR" "$WALLET_NAME" --unsafe-password "$PASSWORD"

                        echo ""
                        echo "Wallet created successfully at: $ETH_WALLET_FILE"
                        echo ""
                        echo "IMPORTANT: Back up your keystore file securely!"
                        echo "Your wallet address:"
                        ${castCmd} wallet address --keystore "$ETH_WALLET_FILE" --password "$PASSWORD"
                        exit 0
                        ;;
                    *)
                        echo "Aborted."
                        exit 0
                        ;;
                esac
            fi

            # Verify wallet file is readable
            if [[ ! -r "$ETH_WALLET_FILE" ]]; then
                echo "Error: Wallet file is not readable: $ETH_WALLET_FILE"
                echo "Check file permissions"
                exit 1
            fi

            # Check if pass entry exists
            if ! ${passCmd} show "$PASSWORD_STORE_PATH" &>/dev/null; then
                echo "Error: Could not retrieve password from pass store at '$PASSWORD_STORE_PATH'"
                echo "Make sure the password store entry exists and is accessible"
                echo ""
                echo "To create the entry, run: pass insert $PASSWORD_STORE_PATH"
                exit 1
            fi

            # Get password from pass
            PASSWORD=$(${passCmd} show "$PASSWORD_STORE_PATH")

            # Validate password is not empty
            if [[ -z "$PASSWORD" ]]; then
                echo "Error: Password retrieved from pass store is empty"
                exit 1
            fi

            # If no arguments provided, show wallet address and usage hint
            if [[ $# -eq 0 ]]; then
                echo "Ethereum Wallet: $WALLET_NAME"
                echo "Keystore: $ETH_WALLET_FILE"
                echo "RPC: $RPC_URL"
                echo ""
                echo "Address:"
                ${castCmd} wallet address --keystore "$ETH_WALLET_FILE" --password "$PASSWORD"
                echo ""
                echo "Run 'ethereum-wallet --help' for available commands"
                exit 0
            fi

            # Handle --help specially to show both cast help and wrapper info
            if [[ "$1" == "--help" || "$1" == "-h" ]]; then
                echo "ethereum-wallet - Ethereum wallet wrapper using cast (foundry)"
                echo ""
                echo "USAGE:"
                echo "  ethereum-wallet [COMMAND] [ARGS...]"
                echo ""
                echo "ENVIRONMENT VARIABLES:"
                echo "  WALLET                    Wallet name (default: main_wallet)"
                echo "  ETH_WALLET_DIR            Wallet directory (default: ~/Shared/Coins/ethereum)"
                echo "  ETH_WALLET_FILE           Wallet file path (default: \$ETH_WALLET_DIR/\$WALLET)"
                echo "  ETH_PASSWORD_STORE_PATH   Pass entry path (default: ethereum/\$WALLET)"
                echo "  ETH_RPC_URL               RPC endpoint (default: https://eth.llamarpc.com)"
                echo ""
                echo "EXAMPLES:"
                echo "  ethereum-wallet                           # Show wallet address"
                echo "  ethereum-wallet balance <ADDRESS>         # Check balance"
                echo "  ethereum-wallet send <TO> --value 0.1ether  # Send ETH"
                echo "  ethereum-wallet nonce <ADDRESS>           # Get nonce"
                echo "  WALLET=savings ethereum-wallet            # Use different wallet"
                echo ""
                echo "CAST COMMANDS:"
                ${castCmd} --help
                exit 0
            fi

            # For wallet subcommands, inject keystore args
            if [[ "$1" == "wallet" ]]; then
                shift
                exec ${castCmd} wallet "$@" --keystore "$ETH_WALLET_FILE" --password "$PASSWORD"
            fi

            # For send command, inject keystore args for signing
            if [[ "$1" == "send" ]]; then
                shift
                exec ${castCmd} send "$@" --keystore "$ETH_WALLET_FILE" --password "$PASSWORD"
            fi

            # For mktx command (build unsigned tx), inject keystore args
            if [[ "$1" == "mktx" ]]; then
                shift
                exec ${castCmd} mktx "$@" --keystore "$ETH_WALLET_FILE" --password "$PASSWORD"
            fi

            # For other commands, pass through directly (they may not need signing)
            exec ${castCmd} "$@"
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
    };
}
