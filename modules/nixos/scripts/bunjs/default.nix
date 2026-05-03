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
    let
      bunScriptsSrc = pkgs.lib.cleanSourceWith {
        src = ./.;
        filter =
          path: type:
          let
            name = baseNameOf path;
          in
          # Nix must build from declared locks, not from mutable editor/runtime
          # installs. These names are Bun/npm cache outputs from local dev.
          !(builtins.elem name [
            "node_modules"
            ".bun"
            "dist"
            "coverage"
          ]);
      };

      playwrightStealthEnv = pkgs.runCommandLocal "playwright-stealth-env" { } ''
        mkdir -p "$out/node_modules"
        cp ${./playwright-stealth-browser.ts} "$out/playwright-stealth-browser.ts"

        # Bun resolves bare imports relative to the script path, so expose the
        # nixpkgs Playwright package under the expected node_modules name.
        # This keeps the launcher reproducible without depending on a checkout's
        # mutable Bun workspace install.
        ln -s ${pkgs.playwright} "$out/node_modules/playwright-core"
      '';

      bunScriptBundles = pkgs.buildNpmPackage {
        pname = "bun-script-bundles";
        version = "0-unstable";
        src = bunScriptsSrc;

        # nixpkgs still lacks a first-party Bun lockfile builder on this channel,
        # so we import the npm lock once and then use Bun only for bundling.
        # This keeps packaged outputs independent from repo-local node_modules.
        # Ref: https://github.com/NixOS/nixpkgs/blob/master/doc/languages-frameworks/javascript.section.md#importnpmlock
        npmDeps = pkgs.importNpmLock {
          npmRoot = bunScriptsSrc;
        };
        npmConfigHook = pkgs.importNpmLock.npmConfigHook;
        npmFlags = [ "--legacy-peer-deps" ];

        nativeBuildInputs = [ pkgs.bun ];
        PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";

        buildPhase = ''
          runHook preBuild

          export HOME="$TMPDIR"
          export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
          export VPN_PROXY_WEB_DIST="$PWD/proxy/web-ui/dist"

          bun run build:web-ui

          mkdir -p bundled
          bun build --target=bun --outfile=bundled/image-gen-mcp.js mcp/image-gen.ts
          bun build --target=bun --outfile=bundled/passmenu.js passmenu.ts
          bun build --target=bun --outfile=bundled/markdown-lint-mcp.js mcp/markdown-lint.ts
          bun build --target=bun --outfile=bundled/quickshell-docs-mcp.js mcp/quickshell-docs.ts
          bun build --target=bun --outfile=bundled/qmllint-mcp.js mcp/qmllint.ts
          bun build --target=bun --outfile=bundled/vpn-proxy-web.js proxy/web-server.ts

          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall

          mkdir -p "$out/share/bunjs" "$out/share/vpn-proxy-web"
          cp bundled/*.js "$out/share/bunjs/"
          cp -r proxy/web-ui/dist "$out/share/vpn-proxy-web/dist"

          runHook postInstall
        '';
      };
    in
    {
      packages.dictation = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "dictation" ''
          exec ${pkgs.bun}/bin/bun run ${./dictation.ts} "$@"
        '';

        runtimeInputs = [
          self'.packages.toggle-dictation-overlay
          pkgs.bun
          pkgs.wtype
          pkgs.wl-clipboard
          pkgs.coreutils
          #pkgs.whisper-cpp # using whisper-cpp as a runtimeInput makes it not work.
          pkgs.ffmpeg
          pkgs.jq
        ];
      };

      packages.qs-passmenu = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "qs-passmenu" ''
          exec ${pkgs.bun}/bin/bun ${bunScriptBundles}/share/bunjs/passmenu.js "$@"
        '';

        # Ensure PATH includes all runtime inputs
        runtimeInputs = [
          (pkgs.pass.withExtensions (exts: [ exts.pass-otp ])) # Password management
          pkgs.gnupg
          self'.packages.qs-dmenu
          pkgs.wl-clipboard
          # pkgs.xclip
          # pkgs.wtype
          pkgs.wl-clipboard
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

      # MCP servers import the SDK from package.json, so ship bundled entrypoints
      # instead of relying on a checked-out node_modules tree at runtime.
      packages.image-gen-mcp = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "image-gen-mcp" ''
          exec ${pkgs.bun}/bin/bun ${bunScriptBundles}/share/bunjs/image-gen-mcp.js "$@"
        '';
        runtimeInputs = [
          pkgs.bun
          pkgs.coreutils
        ];
      };

      packages.markdown-lint-mcp = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "markdown-lint-mcp" ''
          exec ${pkgs.bun}/bin/bun ${bunScriptBundles}/share/bunjs/markdown-lint-mcp.js "$@"
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
          exec ${pkgs.bun}/bin/bun ${bunScriptBundles}/share/bunjs/quickshell-docs-mcp.js "$@"
        '';
        runtimeInputs = [
          pkgs.bun
          pkgs.coreutils
        ];
      };

      packages.qmllint-mcp = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "qmllint-mcp" ''
          exec ${pkgs.bun}/bin/bun ${bunScriptBundles}/share/bunjs/qmllint-mcp.js "$@"
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
            cp ${./proxy/settings.ts} $out/settings.ts
            cp ${./proxy/proxy-tester.ts} $out/proxy-tester.ts
            cp ${./proxy/cli-tools.ts} $out/cli-tools.ts
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
            cp ${./proxy/settings.ts} $out/settings.ts
            cp ${./proxy/proxy-tester.ts} $out/proxy-tester.ts
            cp ${./proxy/cli-tools.ts} $out/cli-tools.ts
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
            pkgs.dante
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
            cp ${./proxy/settings.ts} $out/settings.ts
            cp ${./proxy/proxy-tester.ts} $out/proxy-tester.ts
            cp ${./proxy/cli-tools.ts} $out/cli-tools.ts
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
            pkgs.dante
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
            cp ${./proxy/settings.ts} $out/settings.ts
            cp ${./proxy/proxy-tester.ts} $out/proxy-tester.ts
            cp ${./proxy/cli-tools.ts} $out/cli-tools.ts
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

      # Web management UI — bundle the Elysia backend and React SPA from the
      # package-lock closure so service startup never depends on a checkout's
      # Bun workspace symlink graph.
      packages.vpn-proxy-web = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "vpn-proxy-web" ''
          export VPN_PROXY_WEB_DIST="${bunScriptBundles}/share/vpn-proxy-web/dist"
          exec ${pkgs.bun}/bin/bun ${bunScriptBundles}/share/bunjs/vpn-proxy-web.js "$@"
        '';
        runtimeInputs = [
          pkgs.bun
          pkgs.curl # health testing uses curl through SOCKS5
          pkgs.coreutils
        ];
      };

      packages.vpn-proxy-singbox-config =
        let
          proxyEnv = pkgs.runCommandLocal "proxy-env" { } ''
            mkdir -p $out
            cp ${./proxy/singbox-config.ts} $out/singbox-config.ts
          '';
        in
        inputs.wrappers.lib.makeWrapper {
          inherit pkgs;
          package = pkgs.writeShellScriptBin "vpn-proxy-singbox-config" ''
            exec ${pkgs.bun}/bin/bun run ${proxyEnv}/singbox-config.ts "$@"
          '';
          runtimeInputs = [
            pkgs.bun
            pkgs.coreutils
          ];
        };

      packages.playwright-stealth-browser =
        let
          # Extract the chromium directory name from the browsers package
          # Keep the Bun workspace's `playwright-core` dependency pinned to the
          # nixpkgs Playwright version so the client protocol matches the
          # store-managed browser revision on NixOS.
          # Ref: https://wiki.nixos.org/wiki/Playwright
          chromiumDir = builtins.head (
            builtins.filter (x: builtins.match "chromium-.*" x != null) (
              builtins.attrNames (builtins.readDir pkgs.playwright-driver.browsers)
            )
          );
          chromiumBin = "${pkgs.playwright-driver.browsers}/${chromiumDir}/chrome-linux/chrome";
        in
        inputs.wrappers.lib.makeWrapper {
          inherit pkgs;
          package = pkgs.writeShellScriptBin "playwright-stealth-browser" ''
            export PLAYWRIGHT_BROWSERS_PATH=${pkgs.playwright-driver.browsers}
            export PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS=true
            export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
            export PLAYWRIGHT_NODEJS_PATH=${pkgs.nodejs}/bin/node
            export PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH="${chromiumBin}"

            exec ${pkgs.bun}/bin/bun run ${playwrightStealthEnv}/playwright-stealth-browser.ts "$@"
          '';

          runtimeInputs = [
            pkgs.bun
            pkgs.nodejs
            pkgs.playwright
            pkgs.playwright-driver.browsers
            pkgs.coreutils
          ];
        };
    };
}
