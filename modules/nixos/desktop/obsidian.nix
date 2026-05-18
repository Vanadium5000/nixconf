{ self, ... }:
{
  flake.nixosModules.obsidian =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (lib)
        mkEnableOption
        mkIf
        mkOption
        optionalAttrs
        types
        ;

      cfg = config.preferences.obsidian;
      user = config.preferences.user.username;
      themeName = cfg.theme.name;
      themeDirectory = cfg.theme.directory;
      vaultPath = "${config.preferences.paths.homeDirectory}/${cfg.vaultDirectory}";

      # Obsidian 1.11+ needs Electron safeStorage backed by libsecret, and
      # nixpkgs exposes commandLineArgs directly on the wrapper used for the
      # native `obsidian` binary.
      # Source: https://obsidian.md/changelog/2026-01-20-desktop-v1.11.5/
      # Source: nixpkgs pkgs/by-name/ob/obsidian/package.nix#L11-L84
      obsidianPackage = pkgs.obsidian.override {
        commandLineArgs = "--password-store=gnome-libsecret";
      };

      # Obsidian's in-app CLI installer follows Electron's process.execPath and
      # can therefore see "electron" instead of the Nix wrapper. Install a real
      # declarative `obsidian` command while preserving the upstream desktop file.
      # Source: nixpkgs pkgs/by-name/ob/obsidian/package.nix wrapper layout.
      obsidianPackageWithCli = pkgs.symlinkJoin {
        name = "obsidian-with-cli";
        paths = [ obsidianPackage ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          rm -f $out/bin/obsidian
          makeWrapper ${obsidianPackage}/bin/obsidian $out/bin/obsidian
        '';
      };

      inherit (self) colors colorsNoHash theme;

      appearanceConfig = {
        accentColor = colors.accent;
        baseFontSize = theme.font-size;
        cssTheme = themeName;
        enabledCssSnippets = [ ];
        theme = "system";
      };

      themeManifest = {
        name = themeName;
        version = "1.0.0";
        minAppVersion = "1.1.0";
        author = "nixconf";
      };

      themeCss = ''
        /**
         * @name ${themeName}
         * @description Generated from modules/theme.nix so Obsidian follows the same palette as the desktop.
         * @source https://github.com/Vanadium5000/nixos-config/blob/cabf2c1c6a36beea003eee1e93f0472f4d98c023/home-manager/desktop/obsidian/templates/obsidian.mustache
         */

        body {
          --base00: #${colorsNoHash.base00};
          --base01: #${colorsNoHash.base01};
          --base02: #${colorsNoHash.base02};
          --base03: #${colorsNoHash.base03};
          --base04: #${colorsNoHash.base04};
          --base05: #${colorsNoHash.base05};
          --base06: #${colorsNoHash.base06};
          --base07: #${colorsNoHash.base07};
          --base08: #${colorsNoHash.base08};
          --base09: #${colorsNoHash.base09};
          --base0A: #${colorsNoHash.base0A};
          --base0B: #${colorsNoHash.base0B};
          --base0C: #${colorsNoHash.base0C};
          --base0D: #${colorsNoHash.base0D};
          --base0E: #${colorsNoHash.base0E};
          --base0F: #${colorsNoHash.base0F};
        }

        .theme-light,
        .theme-dark {
          --color-red: var(--base08);
          --color-orange: var(--base09);
          --color-yellow: var(--base0A);
          --color-green: var(--base0B);
          --color-cyan: var(--base0C);
          --color-blue: var(--base0D);
          --color-purple: var(--base0E);
          --color-pink: var(--base0E);

          --font-interface-theme: "${theme.font}";
          --font-text-theme: "${theme.font}";
          --font-monospace-theme: "${theme.font}";
          --font-ui-smaller: ${builtins.toString theme.font-size}px;
          --font-ui-small: ${builtins.toString theme.font-size}px;
          --font-ui-medium: ${builtins.toString (theme.font-size + 1)}px;

          --background-primary: var(--base00);
          --background-secondary: var(--base01);
          --background-modifier-border: var(--base02);
          --background-modifier-border-focus: var(--base03);
          --background-modifier-hover: var(--base02);
          --background-modifier-active-hover: var(--base02);
          --titlebar-background: var(--background-secondary);
          --titlebar-background-focused: var(--background-primary);
          --modal-background: var(--background-secondary);

          --text-normal: var(--base05);
          --text-muted: var(--base04);
          --text-faint: var(--base03);
          --text-accent: var(--base0D);
          --text-accent-hover: var(--base0C);
          --text-on-accent: var(--base07);
          --text-selection: var(--base02);
          --text-highlight-bg: var(--base0D);

          --interactive-normal: var(--base01);
          --interactive-hover: var(--base02);
          --interactive-accent: var(--base0D);
          --interactive-accent-hover: var(--base0C);

          --h1-color: var(--base0E);
          --h2-color: var(--base0D);
          --h3-color: var(--base0B);
          --h4-color: var(--base0A);
          --h5-color: var(--base09);
          --h6-color: var(--base08);
          --inline-title-color: var(--text-normal);

          --link-color: var(--base0D);
          --link-external-color: var(--base0D);
          --link-color-hover: var(--base0C);
          --link-external-color-hover: var(--base0C);
          --tag-color: var(--base0D);
          --tag-background: var(--base01);
          --tag-background-hover: var(--base02);

          --blockquote-border-color: var(--base0D);
          --hr-color: var(--base03);
          --indentation-guide-color: var(--base03);
          --indentation-guide-color-active: var(--base04);
          --list-marker-color: var(--base0D);

          --code-background: var(--base01);
          --code-normal: var(--base05);
          --code-comment: var(--base03);
          --code-function: var(--base0D);
          --code-important: var(--base0A);
          --code-keyword: var(--base08);
          --code-operator: var(--base0C);
          --code-property: var(--base0D);
          --code-string: var(--base0B);
          --code-tag: var(--base08);
          --code-value: var(--base0E);
        }
      '';
    in
    {
      options.preferences.obsidian = {
        enable = mkEnableOption "Obsidian";

        vaultDirectory = mkOption {
          type = types.str;
          default = "Shared/Vault";
          description = "Primary Obsidian vault path relative to the configured home directory.";
        };

        theme = {
          enable = mkEnableOption "the generated nixconf Obsidian theme" // {
            default = true;
          };

          name = mkOption {
            type = types.str;
            default = "Nixconf Base16";
            description = "Name of the generated theme installed and selected in the primary vault.";
          };

          directory = mkOption {
            type = types.str;
            default = "Nixconf Base16";
            description = "Directory name for the generated theme under .obsidian/themes.";
          };
        };
      };

      config = mkIf cfg.enable {
        environment.systemPackages = [
          obsidianPackageWithCli

          # Keep the libsecret stack explicit so Obsidian Sync's encrypted
          # credentials do not depend on unrelated Electron apps being present.
          # Source: https://obsidian.md/changelog/2026-01-20-desktop-v1.11.5/
          pkgs.gnome-keyring
          pkgs.libsecret
          pkgs.seahorse
        ];

        # GNOME Keyring provides the org.freedesktop.secrets service that Electron
        # can use through libsecret for Obsidian's encrypted credential storage.
        # Source: https://github.com/GNOME/gnome-keyring/blob/947a85a29db0684546ceca95e7d539d5a9e15616/README#L1-L10
        services.gnome.gnome-keyring.enable = true;

        xdg.mime = {
          enable = true;
          # nixpkgs installs obsidian.desktop with the obsidian:// MIME handler;
          # declaring it keeps note links deterministic on fresh graphical hosts.
          # Source: nixpkgs pkgs/by-name/ob/obsidian/package.nix#L50-L57
          defaultApplications."x-scheme-handler/obsidian" = [ "obsidian.desktop" ];
        };

        # Obsidian is unfree; keep this local to the feature instead of widening
        # the repo's global allowUnfree policy.
        # Source: nixpkgs pkgs/by-name/ob/obsidian/package.nix#L17-L22
        preferences.allowedUnfree = [ "obsidian" ];

        # Native Obsidian stores mutable Electron profile state under
        # ~/.config/obsidian, including Chromium Preferences and per-window JSON
        # files where zoom/window state is written. Persist the profile rather
        # than managing those files, otherwise an impermanent root forgets zoom
        # on every boot and package migrations start from a fresh app profile.
        # Source: https://github.com/bezata/kObsidian/blob/main/docs/ENVIRONMENT.md#obsidianjson-paths-per-os
        impermanence.home.directories = [
          ".config/obsidian"
          ".local/share/obsidian"
        ];

        # Chromium/Electron caches are reproducible performance state, not vault
        # data; keep them in the cache tier used by modules/common/impermanence.nix.
        # Assumption: Obsidian follows XDG cache conventions on native Linux.
        impermanence.home.cache.directories = [ ".cache/obsidian" ];

        system.activationScripts.obsidian-user-files = {
          text = self.lib.userFiles.mkActivationScript {
            inherit user;
            inherit pkgs;
            homeDirectory = config.preferences.paths.homeDirectory;
            files = {
              # Native Linux Obsidian reads its vault registry from ~/.config/obsidian;
              # seed only the stable path/open fields so first launch opens Shared/Vault
              # without taking ownership of mutable profile files such as Preferences.
              # Source: https://github.com/bezata/kObsidian/blob/main/docs/ENVIRONMENT.md#obsidianjson-paths-per-os
              ".config/obsidian/obsidian.json" = {
                type = "copy";
                clobber = false;
                text = builtins.toJSON {
                  vaults.nixconf-primary = {
                    path = vaultPath;
                    open = true;
                    ts = 0;
                  };
                };
              };

            }
            // optionalAttrs cfg.theme.enable {
              # Obsidian discovers full app themes from .obsidian/themes/<name> with
              # manifest.json and theme.css. Symlinks can be hidden by Electron file
              # watchers, so copy the files like a manually installed Obsidianite theme.
              # Source: https://github.com/obsidianmd/obsidian-developer-docs/blob/2ed97bd04e82773d81eac967382819431da3b098/en/Themes/App%20themes/Build%20a%20theme.md#L20-L25
              "${cfg.vaultDirectory}/.obsidian/appearance.json" = {
                type = "copy";
                clobber = false;
                text = builtins.toJSON appearanceConfig;
              };
              "${cfg.vaultDirectory}/.obsidian/themes/${themeDirectory}/manifest.json" = {
                type = "copy";
                text = builtins.toJSON themeManifest;
              };
              "${cfg.vaultDirectory}/.obsidian/themes/${themeDirectory}/theme.css" = {
                type = "copy";
                text = themeCss;
              };
            };
          };
          deps = [ "users" ];
        };

        # Shared is already persisted by modules/common/impermanence.nix, so the
        # vault inherits the repo's cross-host sync/persistence convention without
        # adding a second Obsidian-specific persistence root.
      };
    };
}
