{ inputs, self, ... }:
{
  flake.nixosModules.nix =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    {
      imports = [
        inputs.nix-index-database.nixosModules.nix-index
        {
          options.preferences.system.temporaryNixpkgsOverrides = lib.mkOption {
            description = "Temporary package overrides with built-in expiry checks.";
            type = lib.types.attrsOf (
              lib.types.submodule {
                options = self.lib.nixpkgs.temporaryOverrideModule;
              }
            );
            default = self.lib.nixpkgs.temporaryOverrides;
          };
        }
      ];

      # nix-index-database ships pinned nix-locate data plus shell command-not-found
      # hooks; enable comma against its small DB so `, jq` can enter/run packages
      # without a mutable nix-index cache. Source: nix-community/nix-index-database README.
      programs.nix-index-database.comma.enable = true;
      programs.nix-index = {
        enableBashIntegration = true;
        enableZshIntegration = true;
      };
      programs.command-not-found.enable = false;
      programs.zsh.enable = true;

      nix = {
        settings.experimental-features = [
          "nix-command"
          "flakes"
        ];
        package = pkgs.lix;

        # Weekly cleanup keeps store growth bounded; 14d preserves a small rollback buffer.
        # See https://search.nixos.org/options?query=nix.gc.options
        gc = {
          automatic = true;
          dates = "weekly";
          options = "--delete-older-than 14d";
        };

        # Weekly optimisation re-links duplicate store paths after cleanup.
        # See https://search.nixos.org/options?query=nix.optimise.dates
        optimise = {
          automatic = true;
          dates = [ "weekly" ];
        };

        # Opinionated: disable channels
        channel.enable = false;

        # Workaround for https://github.com/NixOS/nix/issues/9574
        nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];

        # Keep CLI `flake:nixpkgs-unstable` aligned with this flake's locked input,
        # so ad-hoc `nix run/shell/build` usage cannot drift to user/global registry pins.
        registry.nixpkgs-unstable.flake = inputs.nixpkgs-unstable;

        settings = {
          builders-use-substitutes = true;
          trusted-users = [
            config.preferences.user.username
            "root"
            "@wheel"
          ];

          # Fan out around slow CDN connections; timeouts are seconds.
          # Source: https://nixos.org/manual/nix/stable/command-ref/conf-file#conf-http-connections
          http-connections = 256;
          max-substitution-jobs = 96;
          connect-timeout = 5;
          stalled-download-timeout = 30;
        };
      };
      programs.nix-ld = {
        enable = true;
        libraries = with pkgs; [
          # Extra runtime libs for unpatched binaries that npm/bun download
          # (Chrome for Testing, Playwright/Puppeteer browsers, Electron tools).
          # X11 client libraries are linked by upstream Chromium/Electron builds,
          # not the Xorg server/session; Wayland-only systems still need them.
          alsa-lib
          at-spi2-atk
          at-spi2-core
          atk
          cairo
          coreutils
          cups
          dbus
          dbus-glib
          expat
          ffmpeg
          fontconfig
          freetype
          gdk-pixbuf
          gsettings-desktop-schemas
          glib
          gtk3
          icu
          libcap
          libdrm
          libelf
          libgbm
          libGL
          libGLU
          libnotify
          libusb1
          libva
          libxkbcommon
          libxcrypt
          mesa
          networkmanager
          nspr
          nss
          pango
          pciutils
          pipewire
          SDL2
          stdenv.cc.cc
          udev
          vulkan-loader
          wayland
          zenity
          libice
          libsm
          libx11
          libxscrnsaver
          libxcomposite
          libxcursor
          libxdamage
          libxext
          libxfixes
          libxi
          libxinerama
          libxrandr
          libxrender
          libxt
          libxtst
          libxxf86vm
          libxcb
          libxshmfence
        ];
      };
      nixpkgs.config = self.lib.nixpkgs.mkNixpkgsConfig {
        allowUnfree = false;
        allowedUnfree = self.lib.nixpkgs.allowedUnfree ++ config.preferences.allowedUnfree;
      };

      nixpkgs.overlays = self.lib.nixpkgs.mkSharedOverlays {
        inherit inputs self;
        unstableConfig = finalConfig: finalConfig;
        temporaryOverrides = config.preferences.system.temporaryNixpkgsOverrides;
      };

      # Historical Waydroid override kept with its overlay wrapper so `prev` is in scope
      # if the temporary multi-instance fork needs to be revived.
      # (final: prev: {
      #   waydroid-nftables = prev.waydroid-nftables.overrideAttrs (_old: {
      #     # HACK: Temporary multi-instance override from taksan's fork until upstream merges.
      #     # Undo by deleting this override once https://github.com/waydroid/waydroid/pull/1990 lands.
      #     # Clear inherited nixpkgs patches because this fork's source layout no longer matches
      #     # the 1.5.4 revert patch context, which otherwise breaks evaluation during patchPhase.
      #     src = prev.fetchFromGitHub {
      #       owner = "taksan";
      #       repo = "waydroid";
      #       rev = "bcd79d5fc522fdac514fae1a06efd5f1d4e0d545"; # feat/multi-instance @ 2025-07-29
      #       hash = "sha256-F0++vTKbzOU/Fp2IE9hDZVswNpOVduj4/Z32ALLDI/Q=";
      #     };
      #     patches = [ ];
      #   });
      # })

      environment.systemPackages = with pkgs; [
        # Nix tooling
        nil
        nixd
        statix
        alejandra
        manix
        nix-inspect
      ];
    };
}
