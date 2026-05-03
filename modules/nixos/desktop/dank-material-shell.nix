{ inputs, self, ... }:
{
  flake.nixosModules.dankmemershell =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.preferences.dankMaterialShell;
      dmsProgram = config.programs.dank-material-shell;
      user = config.preferences.user.username;
      homeDirectory = config.preferences.paths.homeDirectory;
      selfpkgs = self.packages.${pkgs.stdenv.hostPlatform.system};
      inherit (self) colors;

      dmsPluginDir = ".config/DankMaterialShell/plugins/toggleLidInhibit";
      toggleLidInhibitPluginQml =
        builtins.replaceStrings
          [ "__LID_STATUS__" "__TOGGLE_LID_INHIBIT__" ]
          [
            "${lib.getExe selfpkgs.lid-status}"
            "${lib.getExe selfpkgs.toggle-lid-inhibit}"
          ]
          (builtins.readFile ./dank-material-shell/toggle-lid-inhibit/ToggleLidInhibitWidget.qml);
      dmsConfigPersistence = self.lib.persistence.mkPersistent {
        method = "bind";
        inherit user;
        fileName = "DankMaterialShell";
        targetFile = "${homeDirectory}/.config/DankMaterialShell";
        isDirectory = true;
      };
      hyprDmsPersistence = self.lib.persistence.mkPersistent {
        method = "bind";
        inherit user;
        fileName = "hypr-dms";
        targetFile = "${homeDirectory}/.config/hypr/dms";
        isDirectory = true;
      };
      hyprDmsFragments = [
        "colors.conf"
        "outputs.conf"
        "layout.conf"
        "cursor.conf"
        "binds.conf"
        "windowrules.conf"
      ];
      dmsThemeId = "nixCyberpunkElectricDark";
      dmsThemeFile = ".config/DankMaterialShell/themes/${dmsThemeId}/theme.json";
      dmsTheme = {
        id = dmsThemeId;
        name = "Nix Cyberpunk Electric Dark";
        version = "1.0.0";
        author = "nixconf";
        description = "Declarative DMS theme generated from modules/theme.nix.";
        sourceDir = dmsThemeId;
        dark = {
          name = "Nix Cyberpunk Electric Dark";
          primary = colors.accent;
          primaryText = colors.background;
          primaryContainer = colors.base02;
          secondary = colors.accent-alt;
          surface = colors.background-alt;
          surfaceText = colors.foreground;
          surfaceVariant = colors.base02;
          surfaceVariantText = colors.foreground-alt;
          surfaceTint = colors.accent;
          background = colors.background;
          backgroundText = colors.foreground-alt;
          outline = colors.border-color;
          surfaceContainer = colors.base01;
          surfaceContainerHigh = colors.base02;
          surfaceContainerHighest = colors.base03;
          error = colors.base08;
          warning = colors.base0A;
          info = colors.base0C;
          matugen_type = "scheme-monochrome";
        };
        light = {
          name = "Nix Cyberpunk Electric Light";
          primary = colors.accent;
          primaryText = colors.base07;
          primaryContainer = colors.base06;
          secondary = colors.accent-alt;
          surface = colors.base07;
          surfaceText = colors.base00;
          surfaceVariant = colors.base06;
          surfaceVariantText = colors.base01;
          surfaceTint = colors.accent;
          background = colors.base07;
          backgroundText = colors.base00;
          outline = colors.border-color-inactive;
          surfaceContainer = colors.base06;
          surfaceContainerHigh = colors.base05;
          surfaceContainerHighest = colors.base04;
          error = colors.base08;
          warning = colors.base09;
          info = colors.base0D;
          matugen_type = "scheme-monochrome";
        };
      };

      # DMS is a graphical user-session shell, not a system daemon; upstream
      # wires it to this target from its NixOS module. Source:
      # https://github.com/AvengeMedia/DankMaterialShell/blob/eb5afcdc40ea5446c27e18552ff4a19f9daf9484/distro/nix/nixos.nix#L21-L43
      graphicalSessionTarget = "graphical-session.target";
    in
    {
      imports = [
        inputs.dms.nixosModules.dank-material-shell
      ];

      options.preferences.dankMaterialShell = {
        enable = lib.mkEnableOption "DankMaterialShell desktop shell";
      };

      config = lib.mkIf cfg.enable {
        assertions = [
          {
            assertion = config.systemd.user.services ? dms;
            message = "DankMaterialShell must expose systemd.user.services.dms when preferences.dankMaterialShell.enable is true.";
          }
          {
            assertion = lib.elem graphicalSessionTarget config.systemd.user.services.dms.wantedBy;
            message = "DankMaterialShell dms.service must be wanted by ${graphicalSessionTarget}.";
          }
        ];

        # Keep the upstream option behind a local preference so hosts can opt in
        # without learning DMS's flake-module namespace. Source:
        # https://danklinux.com/docs/dankmaterialshell/nixos
        programs.dank-material-shell = {
          enable = true;
          package = pkgs.unstable.dms-shell;
          dgop.package = pkgs.unstable.dgop;
          systemd = {
            enable = true;
            target = graphicalSessionTarget;
          };
          enableSystemMonitoring = true;
          enableDynamicTheming = true;
          enableAudioWavelength = true;
          enableClipboardPaste = true;
        };

        # DMS stores editable shell settings and Hyprland fragments under
        # ~/.config; bind them into Shared/Data like opencode so UI changes
        # survive the impermanent root. Source:
        # https://github.com/AvengeMedia/DankMaterialShell/blob/eb5afcdc40ea5446c27e18552ff4a19f9daf9484/core/internal/config/deployer.go#L562-L567
        system.activationScripts.dank-material-shell-persistence = {
          text =
            dmsConfigPersistence.activationScript
            + hyprDmsPersistence.activationScript
            + ''
              HYPR_DMS_DIR="${homeDirectory}/.config/hypr/dms"
              mkdir -p "$HYPR_DMS_DIR"
              ${lib.concatMapStringsSep "\n" (fragment: ''touch "$HYPR_DMS_DIR/${fragment}"'') hyprDmsFragments}
              chown -R ${user}:users "$HYPR_DMS_DIR"
            '';
          deps = [ "users" ];
        };

        fileSystems = dmsConfigPersistence.fileSystems // hyprDmsPersistence.fileSystems;

        # DMS registry themes are loaded from <theme>/theme.json; generating only
        # that required file keeps previews optional while making the palette
        # reproducible from modules/theme.nix. Source:
        # https://github.com/AvengeMedia/DankMaterialShell/blob/eb5afcdc40ea5446c27e18552ff4a19f9daf9484/docs/CUSTOM_THEMES.md#theme-structure
        hjem.users.${user}.files = {
          ${dmsThemeFile}.text = builtins.toJSON dmsTheme;

          # DMS scans user plugins from ~/.config/DankMaterialShell/plugins and
          # gives them priority over /etc/xdg system plugins. Installing this
          # local widget there matches user-installed plugins and avoids stale
          # system-plugin component caches. Source:
          # https://github.com/AvengeMedia/DankMaterialShell/blob/eb5afcdc40ea5446c27e18552ff4a19f9daf9484/quickshell/Services/PluginService.qml#L21-L29
          "${dmsPluginDir}/plugin.json".text =
            builtins.readFile ./dank-material-shell/toggle-lid-inhibit/plugin.json;
          "${dmsPluginDir}/ToggleLidInhibitWidget.qml".text = toggleLidInhibitPluginQml;
        };

        # Mirror the upstream user unit locally so installing `dms-shell` cannot
        # be mistaken for a runnable shell service if upstream wiring changes.
        # mkDefault keeps the imported DMS module authoritative when present.
        systemd.user.services.dms = {
          description = lib.mkDefault "DankMaterialShell";
          wantedBy = lib.mkDefault [ graphicalSessionTarget ];
          partOf = lib.mkDefault [ graphicalSessionTarget ];
          after = lib.mkDefault [ graphicalSessionTarget ];

          serviceConfig = {
            ExecStart = lib.mkDefault "${lib.getExe dmsProgram.package} run --session";
            Restart = lib.mkDefault "on-failure";
          };
        };
      };
    };
}
