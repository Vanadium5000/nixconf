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
      packages.dictation = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "dictation" ''
          exec ${pkgs.bun}/bin/bun run ${./dictation.ts} "$@"
        '';

        runtimeInputs = [
          self'.packages.toggle-lyrics-overlay
          pkgs.bun
          pkgs.wtype
          pkgs.coreutils
          #pkgs.whisper-cpp # using whisper-cpp as a runtimeInput makes it not work.
          pkgs.ffmpeg
          pkgs.jq
        ];
      };

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
          export ROFI_IMAGES="${self'.packages.rofi-images}/bin/rofi"
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

      packages.synced-lyrics = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "synced-lyrics" ''
          exec ${pkgs.bun}/bin/bun run ${./synced-lyrics.ts} "$@"
        '';

        # Ensure PATH includes all runtime inputs
        runtimeInputs = [
          pkgs.bun
          pkgs.nodejs_latest
          pkgs.playerctl
          self'.packages.toggle-lyrics-overlay

          # Core utilities
          pkgs.coreutils
        ];
      };
      packages.pomodoro = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "pomodoro" ''
          exec ${pkgs.bun}/bin/bun run ${./pomodoro.ts} "$@"
        '';

        # Ensure PATH includes all runtime inputs
        runtimeInputs = [
          pkgs.bun
          pkgs.libnotify
          pkgs.libcanberra-gtk3
          pkgs.curl
          pkgs.coreutils
        ];
      };

      packages.markdown-lint-mcp = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "markdown-lint-mcp" ''
          exec ${pkgs.bun}/bin/bun run ${./mcp/markdown-lint.ts} "$@"
        '';

        # Ensure PATH includes all runtime inputs
        runtimeInputs = [
          pkgs.bun
          pkgs.nodePackages.markdownlint-cli
          pkgs.coreutils
        ];
      };
    };
}
