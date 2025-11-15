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
    };
}
