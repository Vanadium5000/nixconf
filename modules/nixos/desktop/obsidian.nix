{ inputs, self, ... }:
{
  flake.nixosModules.obsidian =
    {
      config,
      lib,
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
      flatpakAppId = "md.obsidian.Obsidian";
      snippetName = cfg.theme.snippetName;
      vaultPath = "${config.preferences.paths.homeDirectory}/${cfg.vaultDirectory}";

      inherit (self) colors colorsNoHash theme;

      appearanceConfig = {
        accentColor = colors.accent;
        baseFontSize = theme.font-size;
        enabledCssSnippets = [ snippetName ];
        theme = "system";
      };

      themeCss = ''
        /**
         * @name nixconf base16
         * @description Generated from modules/theme.nix so Obsidian follows the same palette as the desktop.
         * @source https://github.com/Vanadium5000/nixos-config/blob/cabf2c1c6a36beea003eee1e93f0472f4d98c023/home-manager/desktop/obsidian/templates/obsidian.mustache
         */

        :root {
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
      imports = [ inputs.nix-flatpak.nixosModules.nix-flatpak ];

      options.preferences.obsidian = {
        enable = mkEnableOption "Obsidian";

        vaultDirectory = mkOption {
          type = types.str;
          default = "Shared/Vault";
          description = "Primary Obsidian vault path relative to the configured home directory.";
        };

        theme = {
          enable = mkEnableOption "the generated nixconf Obsidian CSS snippet" // {
            default = true;
          };

          snippetName = mkOption {
            type = types.str;
            default = "nixconf-base16";
            description = "Name of the generated CSS snippet enabled in the primary vault.";
          };
        };
      };

      config = mkIf cfg.enable {
        services.flatpak = {
          enable = true;
          # Keep Obsidian aligned with the referenced setup, which installs the
          # Flathub app ID instead of relying on the unfree nixpkgs Electron app.
          # Source: https://github.com/Vanadium5000/nixos-config/blob/cabf2c1c6a36beea003eee1e93f0472f4d98c023/home-manager/desktop/obsidian/default.nix#L13-L15
          packages = [ flatpakAppId ];
        };

        xdg.mime = {
          enable = true;
          # Obsidian desktop files register the URI scheme used by obsidian://
          # links; setting it declaratively keeps note links working on fresh
          # graphical hosts after Flatpak exports are added to XDG_DATA_DIRS.
          defaultApplications."x-scheme-handler/obsidian" = [ "${flatpakAppId}.desktop" ];
        };

        hjem.users.${user}.files = {
          # Flatpak scopes app config under ~/.var/app/<app-id>; managing the
          # registry makes Shared/Vault the primary vault without a first-run
          # click path. The schema is Obsidian-internal, so keep only the stable
          # path/open fields plus a deterministic timestamp for one Nix-managed
          # vault entry.
          # Source: https://github.com/bezata/kObsidian/blob/main/docs/ENVIRONMENT.md#obsidianjson-paths-per-os
          ".var/app/${flatpakAppId}/config/obsidian/obsidian.json".text = builtins.toJSON {
            vaults.nixconf-primary = {
              path = vaultPath;
              open = true;
              ts = 0;
            };
          };
        }
        // optionalAttrs cfg.theme.enable {
          # The upstream reference enables a generated Base16 CSS snippet via
          # .obsidian/appearance.json; doing the same here ties notes to
          # modules/theme.nix rather than mutable in-app theme choices.
          # Source: https://github.com/Vanadium5000/nixos-config/blob/cabf2c1c6a36beea003eee1e93f0472f4d98c023/home-manager/desktop/obsidian/theme.nix#L20-L33
          "${cfg.vaultDirectory}/.obsidian/appearance.json".text = builtins.toJSON appearanceConfig;
          "${cfg.vaultDirectory}/.obsidian/snippets/${snippetName}.css".text = themeCss;
        };

        # Shared is already persisted by modules/common/impermanence.nix, so the
        # vault inherits the repo's cross-host sync/persistence convention without
        # adding a second Obsidian-specific persistence root.
      };
    };
}
