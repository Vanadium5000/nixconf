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
      shellEdgePkgs = pkgs.unstable;
      user = config.preferences.user.username;
      homeDirectory = config.preferences.paths.homeDirectory;
      selfpkgs = self.packages.${pkgs.stdenv.hostPlatform.system};
      inherit (self) colors;
      dmsCommonSrc = pkgs.fetchFromGitHub {
        owner = "hthienloc";
        repo = "dms-common";
        rev = "ae66a020129e6226d28dc6e581a21bf68087efc6";
        hash = "sha256-nLY1oeSOocma2dOWMfU9Yz+wAFHYSg4MyZpjSi4I+pg=";
      };

      idleInhibitPluginDir = ".config/DankMaterialShell/plugins/idleInhibit";
      toggleLidInhibitPluginDir = ".config/DankMaterialShell/plugins/toggleLidInhibit";
      voxtypeWidgetPluginDir = ".config/DankMaterialShell/plugins/voxtypeWidget";
      dmsCommonPluginDir = ".config/DankMaterialShell/plugins/dms-common";
      idleInhibitPluginQml =
        builtins.replaceStrings [ "__DMS_IDLE_INHIBIT__" ] [ "${lib.getExe selfpkgs.dms-idle-inhibit}" ]
          (builtins.readFile ./dank-material-shell/idle-inhibit/IdleInhibitWidget.qml);
      idleInhibitPluginQmlFile = pkgs.writeText "IdleInhibitWidget.qml" idleInhibitPluginQml;
      toggleLidInhibitPluginQml =
        builtins.replaceStrings
          [ "__TOGGLE_LID_INHIBIT__" ]
          [
            "${lib.getExe selfpkgs.toggle-lid-inhibit}"
          ]
          (builtins.readFile ./dank-material-shell/toggle-lid-inhibit/ToggleLidInhibitWidget.qml);
      voxtypeWidgetPluginQml =
        builtins.replaceStrings
          [
            "__VOXTYPE__"
            "__SYSTEMCTL__"
            "__SH__"
            "__WTYPE__"
            "__WL_COPY__"
            "__NOTIFY_SEND__"
          ]
          [
            "${lib.getExe shellEdgePkgs.voxtype}"
            "${pkgs.systemd}/bin/systemctl"
            "${pkgs.bash}/bin/sh"
            "${lib.getExe pkgs.wtype}"
            "${pkgs.wl-clipboard}/bin/wl-copy"
            "${pkgs.libnotify}/bin/notify-send"
          ]
          (builtins.readFile ./dank-material-shell/voxtype-widget/VoxtypeWidget.qml);
      voxtypeModelsPersistence = self.lib.persistence.mkPersistent {
        method = "bind";
        inherit user;
        fileName = "voxtype-models";
        targetFile = "${homeDirectory}/.local/share/voxtype/models";
        isDirectory = true;
      };
      idleInhibitPersistence = self.lib.persistence.mkPersistent {
        method = "bind";
        inherit user;
        fileName = "dms-idle-inhibit";
        targetFile = "${homeDirectory}/.local/state/dms-idle-inhibit";
        isDirectory = true;
      };
      dmsConfigPersistence = self.lib.persistence.mkPersistent {
        method = "bind";
        inherit user;
        fileName = "DankMaterialShell";
        targetFile = "${homeDirectory}/.config/DankMaterialShell";
        isDirectory = true;
      };
      dmsStatePersistence = [ ".local/state/DankMaterialShell" ];
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
      voxtypeConfigFile = ".config/voxtype/config.toml";
      voxtypeConfig = ''
        state_file = "auto"
        engine = "whisper"

        [hotkey]
        enabled = false
        key = "SCROLLLOCK"
        modifiers = []
        mode = "toggle"

        [audio]
        device = "default"
        sample_rate = 16000
        max_duration_secs = 60

        [audio.feedback]
        enabled = false
        theme = "default"
        volume = 0.7

        [whisper]
        model = "base.en"
        language = "en"
        translate = false
        # Keep the small model resident so external start/stop triggers do not
        # race the first model load and appear to record/transcribe nothing.
        on_demand_loading = false

        [output]
        mode = "type"
        fallback_to_clipboard = true
        type_delay_ms = 0
        pre_type_delay_ms = 100

        [output.notification]
        on_recording_start = false
        on_recording_stop = false
        on_transcription = true
      '';
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
          package = shellEdgePkgs.dms-shell;
          dgop.package = shellEdgePkgs.dgop;
          systemd = {
            enable = true;
            target = graphicalSessionTarget;
          };
          enableSystemMonitoring = true;
          enableDynamicTheming = true;
          enableAudioWavelength = true;
          enableClipboardPaste = true;
        };

        # DMS stores editable shell settings and Hyprland fragments under ~/.config;
        # plugin runtime state is XDG state, so persist it without Shared/Data sync.
        # Sources:
        # https://github.com/AvengeMedia/DankMaterialShell/blob/eb5afcdc40ea5446c27e18552ff4a19f9daf9484/core/internal/config/deployer.go#L562-L567
        # https://github.com/AvengeMedia/DankMaterialShell/blob/0e9b21d359e754313a9aad17d2b619d616fd643e/quickshell/Common/Paths.qml#L11-L14
        # https://github.com/AvengeMedia/DankMaterialShell/blob/0e9b21d359e754313a9aad17d2b619d616fd643e/quickshell/Services/PluginService.qml#L604-L668
        system.activationScripts.dank-material-shell-persistence = {
          text =
            dmsConfigPersistence.activationScript
            + hyprDmsPersistence.activationScript
            + voxtypeModelsPersistence.activationScript
            + idleInhibitPersistence.activationScript
            + ''
              HYPR_DMS_DIR="${homeDirectory}/.config/hypr/dms"
              mkdir -p "$HYPR_DMS_DIR"
              ${lib.concatMapStringsSep "\n" (fragment: ''
                if [ ! -e "$HYPR_DMS_DIR/${fragment}" ]; then
                  install -D -m 0644 /dev/null "$HYPR_DMS_DIR/${fragment}"
                fi
              '') hyprDmsFragments}
              chown -R ${user}:users "$HYPR_DMS_DIR"

              # ~/.config/DankMaterialShell is itself a persisted bind mount, so
              # place the locally shipped plugin directly into that live tree as
              # well as through the activation-managed user files below. This keeps
              # it visible in DMS's plugin picker immediately after rebuild/reboot.
              IDLE_INHIBIT_PLUGIN_DIR="${homeDirectory}/${idleInhibitPluginDir}"
              install -D -m 0644 ${./dank-material-shell/idle-inhibit/plugin.json} "$IDLE_INHIBIT_PLUGIN_DIR/plugin.json"
              install -D -m 0644 ${idleInhibitPluginQmlFile} "$IDLE_INHIBIT_PLUGIN_DIR/IdleInhibitWidget.qml"
              chown -R ${user}:users "$IDLE_INHIBIT_PLUGIN_DIR"
            '';
          deps = [ "users" ];
        };

        impermanence.home.directories = dmsStatePersistence;

        fileSystems =
          dmsConfigPersistence.fileSystems
          // hyprDmsPersistence.fileSystems
          // voxtypeModelsPersistence.fileSystems
          // idleInhibitPersistence.fileSystems;

        environment.systemPackages = [
          shellEdgePkgs.voxtype
          selfpkgs.dms-idle-inhibit
          selfpkgs.dms-suspend-after
          pkgs.qrencode # Runtime dependency for the user-installed DMS QR generator plugin.
          pkgs.zbar # Optional QR image decoding path used by the same plugin.
          pkgs.qt6Packages.qtmultimedia # DMS settings sound previews import QtMultimedia on Qt 6.
        ];

        # DMS registry themes are loaded from <theme>/theme.json; generating only
        # that required file keeps previews optional while making the palette
        # reproducible from modules/theme.nix. Source:
        # https://github.com/AvengeMedia/DankMaterialShell/blob/eb5afcdc40ea5446c27e18552ff4a19f9daf9484/docs/CUSTOM_THEMES.md#theme-structure
        system.activationScripts.dank-material-shell-user-files = {
          text = self.lib.userFiles.mkActivationScript {
            inherit user homeDirectory;
            inherit pkgs;
            files = {
              ${dmsThemeFile}.text = builtins.toJSON dmsTheme;
              ${voxtypeConfigFile}.text = voxtypeConfig;

              # DMS scans user plugins from ~/.config/DankMaterialShell/plugins and
              # gives them priority over /etc/xdg system plugins. Installing this
              # local widget there matches user-installed plugins and avoids stale
              # system-plugin component caches. Source:
              # https://github.com/AvengeMedia/DankMaterialShell/blob/eb5afcdc40ea5446c27e18552ff4a19f9daf9484/quickshell/Services/PluginService.qml#L21-L29
              "${dmsCommonPluginDir}".source = dmsCommonSrc;
              "${idleInhibitPluginDir}/plugin.json".text =
                builtins.readFile ./dank-material-shell/idle-inhibit/plugin.json;
              "${idleInhibitPluginDir}/IdleInhibitWidget.qml".text = idleInhibitPluginQml;
              "${toggleLidInhibitPluginDir}/plugin.json".text =
                builtins.readFile ./dank-material-shell/toggle-lid-inhibit/plugin.json;
              "${toggleLidInhibitPluginDir}/ToggleLidInhibitWidget.qml".text = toggleLidInhibitPluginQml;
              "${voxtypeWidgetPluginDir}/plugin.json".text =
                builtins.readFile ./dank-material-shell/voxtype-widget/plugin.json;
              "${voxtypeWidgetPluginDir}/VoxtypeWidget.qml".text = voxtypeWidgetPluginQml;
            };
          };
          deps = [ "users" ];
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
            # DMS-spawned apps need the same KDE/Qt markers as the compositor
            # session, or Kirigami can ignore kdeglobals and stay on Breeze.
            # Source: /tmp/plasma-systemmonitor-live-theme.trace
            Environment = [
              "QT_QPA_PLATFORM=wayland"
              "QT_QPA_PLATFORMTHEME=hyprqt6engine"
              "QT_QUICK_CONTROLS_STYLE=org.kde.desktop"
              "QML2_IMPORT_PATH=${pkgs.qt6Packages.qtmultimedia}/lib/qt-6/qml"
              "KDE_FULL_SESSION=true"
              "KDE_SESSION_VERSION=6"
            ];
          };
        };

        systemd.user.services.voxtype = {
          description = "Voxtype push-to-talk voice typing daemon";
          wantedBy = [ graphicalSessionTarget ];
          partOf = [ graphicalSessionTarget ];
          after = [
            graphicalSessionTarget
            "pipewire.service"
            "pipewire-pulse.service"
          ];

          serviceConfig = {
            ExecStart = "${lib.getExe shellEdgePkgs.voxtype} daemon";
            Restart = "on-failure";
            RestartSec = 5;
          };
        };

        systemd.user.services.dms-idle-inhibitor = {
          description = "Persistent idle and sleep inhibitor";
          wantedBy = [ "default.target" ];

          serviceConfig = {
            Type = "exec";
            ExecStart = "${lib.getExe selfpkgs.dms-idle-inhibit} daemon";
            Restart = "on-failure";
            RestartSec = 5;
          };
        };
      };
    };
}
