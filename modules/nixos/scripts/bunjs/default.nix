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
      packages.rofi-passmenu = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "rofi-passmenu" ''
          exec ${pkgs.bun}/bin/bun run ${./passmenu.ts} "$@"
        '';

        # Ensure PATH includes all runtime inputs
        runtimeInputs = [
          (pkgs.pass.withExtensions (exts: [ exts.pass-otp ])) # Password management
          pkgs.gnupg
          self'.packages.rofi
          pkgs.wl-clipboard
          # pkgs.xclip
          # pkgs.wtype
          pkgs.ydotool
          pkgs.bun
          pkgs.nodejs_latest
          pkgs.libnotify

          # Core utilities
          pkgs.coreutils
          pkgs.findutils
          pkgs.gnused
          pkgs.which
        ];
      };

      packages.rofi-checklist = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "rofi-checklist" ''
          exec ${pkgs.bun}/bin/bun run ${./checklist.ts} "$@"
        '';

        # Ensure PATH includes all runtime inputs
        runtimeInputs = [
          self'.packages.rofi
          pkgs.bun
          pkgs.nodejs_latest
          pkgs.libnotify

          # Core utilities
          pkgs.coreutils
          pkgs.findutils
          pkgs.gnused
          pkgs.which
        ];
      };

      packages.btrfs-backup = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "btrfs-backup" ''
          # Ensure we're running as root
          if [ "$(id -u)" -ne 0 ]; then
            exec pkexec env HOST="$HOST" ${pkgs.bun}/bin/bun run ${./btrfs-backup.ts} "$@"
          else
            exec ${pkgs.bun}/bin/bun run ${./btrfs-backup.ts} "$@"
          fi
        '';

        # Ensure PATH includes all runtime inputs
        runtimeInputs = [
          self'.packages.rofi
          pkgs.bun
          pkgs.nodejs_latest
          pkgs.libnotify

          # BTRFS and mount utilities
          pkgs.btrfs-progs
          pkgs.util-linux

          # Core utilities
          pkgs.coreutils
          pkgs.findutils
          pkgs.gnused
          pkgs.which
        ];
      };

      packages.rofi-music-search = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "rofi-music-search" ''
          exec ${pkgs.bun}/bin/bun run ${./music-search.ts} "$@"
        '';

        # Ensure PATH includes all runtime inputs
        runtimeInputs = [
          self'.packages.rofi
          pkgs.bun
          pkgs.nodejs_latest
          pkgs.libnotify
          pkgs.yt-dlp
          pkgs.mpc
          pkgs.curl
          pkgs.ffmpeg # for yt-dlp audio conversion usually

          # Core utilities
          pkgs.coreutils
          pkgs.findutils
          pkgs.gnused
          pkgs.which
        ];
      };
    };
}
