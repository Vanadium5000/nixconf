{
  inputs,
  ...
}:
{
  perSystem =
    {
      pkgs,
      self',
      ...
    }:
    {
      packages.passmenu = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "passmenu" ''
          exec ${pkgs.bun}/bin/bun run ${./passmenu.ts} "$@"
        '';
        env = {
          # Ensure PATH includes all runtime inputs
          PATH = pkgs.lib.makeBinPath [
            (pkgs.pass.withExtensions (exts: [ exts.pass-otp ])) # Password management
            pkgs.gnupg
            self'.packages.rofi
            pkgs.wl-clipboard
            pkgs.wtype
            pkgs.ydotool
            pkgs.bun

            # Core utilities
            pkgs.coreutils
            pkgs.findutils
            pkgs.gnused
            pkgs.which
          ];
        };
      };

      packages.sound-change = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "sound-change" ''
          increments="5"
          smallIncrements="1"

          case "$1" in
            mute)
              wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
              ;;
            up)
              increment=''${2:-$increments}
              wpctl set-volume @DEFAULT_AUDIO_SINK@ ''${increment}%+
              ;;
            down)
              increment=''${2:-$increments}
              wpctl set-volume @DEFAULT_AUDIO_SINK@ ''${increment}%-
              ;;
            set)
              volume=''${2:-100}
              wpctl set-volume @DEFAULT_AUDIO_SINK@ ''${volume}%
              ;;
            *)
              echo "Usage: $0 {mute|up [increment]|down [increment]|set [volume]}"
              exit 1
              ;;
          esac
        '';
        env = {
          PATH = pkgs.lib.makeBinPath [
            pkgs.wireplumber # Provides wpctl
          ];
        };
      };

      packages.sound-up = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "sound-up" ''
          exec ${self'.packages.sound-change}/bin/sound-change up 5
        '';
        env = {
          PATH = pkgs.lib.makeBinPath [
            self'.packages.sound-change
          ];
        };
      };

      packages.sound-up-small = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "sound-up-small" ''
          exec ${self'.packages.sound-change}/bin/sound-change up 1
        '';
        env = {
          PATH = pkgs.lib.makeBinPath [
            self'.packages.sound-change
          ];
        };
      };

      packages.sound-down = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "sound-down" ''
          exec ${self'.packages.sound-change}/bin/sound-change down 5
        '';
        env = {
          PATH = pkgs.lib.makeBinPath [
            self'.packages.sound-change
          ];
        };
      };

      packages.sound-down-small = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "sound-down-small" ''
          exec ${self'.packages.sound-change}/bin/sound-change down 1
        '';
        env = {
          PATH = pkgs.lib.makeBinPath [
            self'.packages.sound-change
          ];
        };
      };

      packages.sound-toggle = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "sound-toggle" ''
          exec ${self'.packages.sound-change}/bin/sound-change mute
        '';
        env = {
          PATH = pkgs.lib.makeBinPath [
            self'.packages.sound-change
          ];
        };
      };

      packages.sound-set = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "sound-set" ''
          exec ${self'.packages.sound-change}/bin/sound-change set "$1"
        '';
        env = {
          PATH = pkgs.lib.makeBinPath [
            self'.packages.sound-change
          ];
        };
      };

      packages.rofi-wallpaper = inputs.wrappers.lib.makeWrapper {
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
          pkgs.writeShellScriptBin "rofi-wallpaper" ''
            # Nix magic
            result=$(echo "${
              builtins.concatStringsSep "\n" (builtins.attrNames wallpaperSources ++ [ "Choose a file..." ])
            }" | \
            rofi -dmenu)

            echo $result

            declare -A wallpaperSources=(${
              builtins.concatStringsSep "\n" (
                map (x: ''["${x}"]="${wallpaperSources.${x}}"'') (builtins.attrNames wallpaperSources)
              )
            })

            if [[ $result == "Choose a file..." ]];then
              echo "Choosing a specific file"
              wallPath=$(echo $(rofi -run-command "echo {cmd}" -show filebrowser) | sed 's/^xdg-open //')

              echo "$wallPath"
              hyprctl hyprpaper preload "$wallPath"
              hyprctl hyprpaper wallpaper ",$wallPath"

              # For rofi & hyprlock wallpaper
              cp -f "$wallPath" ~/.current_wallpaper
              exit 0
            fi

            echo "Getting wallDIR"

            wallDIR="''${wallpaperSources["$result"]}"
            echo $wallDIR

            ${self'.packages.rofi-wallpaper-selector}/bin/rofi-wallpaper-selector "$wallDIR"

            exit 0
          '';
        env = {
          PATH = pkgs.lib.makeBinPath [
            self'.packages.rofi-wallpaper-selector
            self'.packages.rofi
            pkgs.hyprland
            pkgs.coreutils
            pkgs.gnused
          ];
        };
      };

      packages.rofi-wallpaper-selector = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "rofi-wallpaper-selector" ''

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

          # Rofi command
          rofi_command="rofi -dmenu -p 'Select Wallpaper'"

          # Sorting Wallpapers
          menu() {
          	# Sort the PICS array
          	IFS=$'\n' sorted_options=($(sort <<<"''${PICS[*]}"))

          	# Place ". random" at the beginning with the random picture as an icon
          	printf "%s\x00icon\x1f%s\n" "$RANDOM_PIC_NAME" "$RANDOM_PIC"

          	for pic_path in "''${sorted_options[@]}"; do
          		pic_name=$(basename "$pic_path")

          		# Displaying .gif to indicate animated images
          		if [[ ! "$pic_name" =~ \.gif$ ]]; then
          			printf "%s\x00icon\x1f%s\n" "$(echo "$pic_name" | cut -d. -f1)" "$pic_path"
          		else
          			printf "%s\n" "$pic_name"
          		fi
          	done
          }

          # Choice of wallpapers
          main() {
          	choice=$(menu | $rofi_command)

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
          cp -f "$result" ~/.current_wallpaper # For rofi wallpaper
        '';
        env = {
          PATH = pkgs.lib.makeBinPath [
            self'.packages.rofi-images
            pkgs.hyprland
            pkgs.coreutils
            pkgs.findutils
            pkgs.gnused
          ];
        };
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
    };
}
