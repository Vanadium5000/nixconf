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

      packages.qs-passmenu = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "qs-passmenu" ''
          exec ${pkgs.bun}/bin/bun run ${./passmenu.ts} "$@"
        '';

        # Ensure PATH includes all runtime inputs
        runtimeInputs = [
          (pkgs.pass.withExtensions (exts: [ exts.pass-otp ])) # Password management
          pkgs.gnupg
          self'.packages.qs-dmenu
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

      packages.qs-checklist = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "qs-checklist" ''
          exec ${pkgs.bun}/bin/bun run ${./checklist.ts} "$@"
        '';

        # Ensure PATH includes all runtime inputs
        runtimeInputs = [
          self'.packages.qs-dmenu
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
            # Pass display env vars so qs-dmenu can connect to the compositor
            exec pkexec env \
              HOST="$HOST" \
              WAYLAND_DISPLAY="$WAYLAND_DISPLAY" \
              XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
              DISPLAY="$DISPLAY" \
              ${pkgs.bun}/bin/bun run ${./btrfs-backup.ts} "$@"
          else
            exec ${pkgs.bun}/bin/bun run ${./btrfs-backup.ts} "$@"
          fi
        '';

        # Ensure PATH includes all runtime inputs
        runtimeInputs = [
          self'.packages.qs-dmenu
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

      packages.qs-music-search = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "qs-music-search" ''
          export QS_DMENU_IMAGES="${self'.packages.qs-dmenu}/bin/qs-dmenu"
          exec ${pkgs.bun}/bin/bun run ${./music-search.ts} "$@"
        '';

        # Ensure PATH includes all runtime inputs
        runtimeInputs = [
          self'.packages.qs-dmenu
          pkgs.bun
          pkgs.nodejs_latest
          pkgs.libnotify
          pkgs.unstable.yt-dlp
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

      packages.qs-music-local = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "qs-music-local" ''
          export QS_DMENU_IMAGES="${self'.packages.qs-dmenu}/bin/qs-dmenu"
          exec ${pkgs.bun}/bin/bun run ${./music-local.ts} "$@"
        '';

        runtimeInputs = [
          self'.packages.qs-dmenu
          pkgs.bun
          pkgs.libnotify
          pkgs.mpc
          pkgs.coreutils
          pkgs.ffmpeg
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

      # MCP servers - run from absolute path for live editing
      # Requires: bun install in /home/matrix/nixconf/modules/nixos/scripts/bunjs
      packages.markdown-lint-mcp = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "markdown-lint-mcp" ''
          exec ${pkgs.bun}/bin/bun run /home/matrix/nixconf/modules/nixos/scripts/bunjs/mcp/markdown-lint.ts "$@"
        '';
        runtimeInputs = [
          pkgs.bun
          pkgs.nodePackages.markdownlint-cli
          pkgs.coreutils
        ];
      };

      packages.quickshell-docs-mcp = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "quickshell-docs-mcp" ''
          export QUICKSHELL_DOCS_PATH="${self'.packages.quickshell-docs-markdown}"
          exec ${pkgs.bun}/bin/bun run /home/matrix/nixconf/modules/nixos/scripts/bunjs/mcp/quickshell-docs.ts "$@"
        '';
        runtimeInputs = [
          pkgs.bun
          pkgs.coreutils
        ];
      };

      packages.qmllint-mcp = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "qmllint-mcp" ''
          exec ${pkgs.bun}/bin/bun run /home/matrix/nixconf/modules/nixos/scripts/bunjs/mcp/qmllint.ts "$@"
        '';
        runtimeInputs = [
          pkgs.bun
          pkgs.qt6.qtdeclarative
          pkgs.coreutils
        ];
      };

      packages.git-sync-debug = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "git-sync-debug" ''
          exec ${pkgs.bun}/bin/bun run ${./git-sync-debug.ts} "$@"
        '';
        runtimeInputs = [
          pkgs.bun
          pkgs.gnupg
          pkgs.openssh
          pkgs.git
          pkgs.coreutils
          pkgs.which
          pkgs.pinentry-qt # Required for pinentry detection test
        ];
      };

      # ========================================================================
      # VPN Proxy Packages
      # All proxy-related TypeScript files are in ./proxy/ subdirectory
      # ========================================================================

      packages.vpn-resolver =
        let
          # Bundle all proxy files together since they import each other
          proxyEnv = pkgs.runCommandLocal "proxy-env" { } ''
            mkdir -p $out
            cp ${./proxy/vpn-resolver.ts} $out/vpn-resolver.ts
            cp ${./proxy/shared.ts} $out/shared.ts
            cp ${./proxy/socks5-proxy.ts} $out/socks5-proxy.ts
            cp ${./proxy/http-proxy.ts} $out/http-proxy.ts
            cp ${./proxy/cleanup.ts} $out/cleanup.ts
            cp ${./proxy/netns.sh} $out/netns.sh
          '';
        in
        inputs.wrappers.lib.makeWrapper {
          inherit pkgs;
          package = pkgs.writeShellScriptBin "vpn-resolver" ''
            exec ${pkgs.bun}/bin/bun run ${proxyEnv}/vpn-resolver.ts "$@"
          '';
          runtimeInputs = [
            pkgs.bun
            pkgs.coreutils
          ];
        };

      packages.vpn-proxy =
        let
          proxyEnv = pkgs.runCommandLocal "proxy-env" { } ''
            mkdir -p $out
            cp ${./proxy/vpn-resolver.ts} $out/vpn-resolver.ts
            cp ${./proxy/shared.ts} $out/shared.ts
            cp ${./proxy/socks5-proxy.ts} $out/socks5-proxy.ts
            cp ${./proxy/http-proxy.ts} $out/http-proxy.ts
            cp ${./proxy/cleanup.ts} $out/cleanup.ts
            cp ${./proxy/netns.sh} $out/netns.sh
          '';
        in
        inputs.wrappers.lib.makeWrapper {
          inherit pkgs;
          package = pkgs.writeShellScriptBin "vpn-proxy" ''
            export VPN_PROXY_NETNS_SCRIPT="${proxyEnv}/netns.sh"
            exec ${pkgs.bun}/bin/bun run ${proxyEnv}/socks5-proxy.ts "$@"
          '';
          runtimeInputs = [
            pkgs.bun
            pkgs.iproute2
            pkgs.iptables
            pkgs.nftables
            pkgs.openvpn
            pkgs.microsocks
            pkgs.libnotify
            pkgs.jq
            pkgs.coreutils
          ];
        };

      packages.http-proxy =
        let
          proxyEnv = pkgs.runCommandLocal "proxy-env" { } ''
            mkdir -p $out
            cp ${./proxy/vpn-resolver.ts} $out/vpn-resolver.ts
            cp ${./proxy/shared.ts} $out/shared.ts
            cp ${./proxy/socks5-proxy.ts} $out/socks5-proxy.ts
            cp ${./proxy/http-proxy.ts} $out/http-proxy.ts
            cp ${./proxy/cleanup.ts} $out/cleanup.ts
            cp ${./proxy/netns.sh} $out/netns.sh
          '';
        in
        inputs.wrappers.lib.makeWrapper {
          inherit pkgs;
          package = pkgs.writeShellScriptBin "http-proxy" ''
            export VPN_PROXY_NETNS_SCRIPT="${proxyEnv}/netns.sh"
            exec ${pkgs.bun}/bin/bun run ${proxyEnv}/http-proxy.ts "$@"
          '';
          runtimeInputs = [
            pkgs.bun
            pkgs.iproute2
            pkgs.iptables
            pkgs.nftables
            pkgs.openvpn
            pkgs.microsocks
            pkgs.libnotify
            pkgs.jq
            pkgs.coreutils
          ];
        };

      packages.vpn-proxy-netns = pkgs.writeShellScriptBin "vpn-proxy-netns" ''
        exec ${pkgs.bash}/bin/bash ${./proxy/netns.sh} "$@"
      '';

      packages.vpn-proxy-cleanup =
        let
          proxyEnv = pkgs.runCommandLocal "proxy-env" { } ''
            mkdir -p $out
            cp ${./proxy/vpn-resolver.ts} $out/vpn-resolver.ts
            cp ${./proxy/shared.ts} $out/shared.ts
            cp ${./proxy/socks5-proxy.ts} $out/socks5-proxy.ts
            cp ${./proxy/http-proxy.ts} $out/http-proxy.ts
            cp ${./proxy/cleanup.ts} $out/cleanup.ts
            cp ${./proxy/netns.sh} $out/netns.sh
          '';
        in
        inputs.wrappers.lib.makeWrapper {
          inherit pkgs;
          package = pkgs.writeShellScriptBin "vpn-proxy-cleanup" ''
            exec ${pkgs.bun}/bin/bun run ${proxyEnv}/cleanup.ts "$@"
          '';
          runtimeInputs = [
            pkgs.bun
            pkgs.iproute2
            pkgs.iptables
            pkgs.nftables
            pkgs.coreutils
          ];
        };
    };
}
