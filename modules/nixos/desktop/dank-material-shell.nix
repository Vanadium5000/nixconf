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
      idleInhibitPluginDir = ".config/DankMaterialShell/plugins/idleInhibit";
      toggleLidInhibitPluginDir = ".config/DankMaterialShell/plugins/toggleLidInhibit";
      voxtypeWidgetPluginDir = ".config/DankMaterialShell/plugins/voxtypeWidget";
      lyricsWidgetPluginDir = ".config/DankMaterialShell/plugins/lyricsWidget";
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
      toggleLidInhibitPluginQmlFile = pkgs.writeText "ToggleLidInhibitWidget.qml" toggleLidInhibitPluginQml;
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
      voxtypeWidgetPluginQmlFile = pkgs.writeText "VoxtypeWidget.qml" voxtypeWidgetPluginQml;
      lyricsWidgetPluginQml =
        builtins.replaceStrings [ "__LYRICSCTL__" ] [ "${lib.getExe selfpkgs.lyricsctl}" ]
          (builtins.readFile ./dank-material-shell/lyrics-widget/LyricsWidget.qml);
      lyricsWidgetPluginQmlFile = pkgs.writeText "LyricsWidget.qml" lyricsWidgetPluginQml;
      localDmsPluginsInstaller = pkgs.writeShellScript "install-local-dms-plugins" ''
        set -euo pipefail

        plugins_dir=${lib.escapeShellArg "${homeDirectory}/.config/DankMaterialShell/plugins"}
        mkdir -p "$plugins_dir"

        copy_file() {
          local source="$1" target="$2"
          install -D -m 0644 "$source" "$target"
        }

        copy_file ${./dank-material-shell/idle-inhibit/plugin.json} "$plugins_dir/idleInhibit/plugin.json"
        copy_file ${idleInhibitPluginQmlFile} "$plugins_dir/idleInhibit/IdleInhibitWidget.qml"
        copy_file ${./dank-material-shell/toggle-lid-inhibit/plugin.json} "$plugins_dir/toggleLidInhibit/plugin.json"
        copy_file ${toggleLidInhibitPluginQmlFile} "$plugins_dir/toggleLidInhibit/ToggleLidInhibitWidget.qml"
        copy_file ${./dank-material-shell/voxtype-widget/plugin.json} "$plugins_dir/voxtypeWidget/plugin.json"
        copy_file ${voxtypeWidgetPluginQmlFile} "$plugins_dir/voxtypeWidget/VoxtypeWidget.qml"
        copy_file ${./dank-material-shell/lyrics-widget/plugin.json} "$plugins_dir/lyricsWidget/plugin.json"
        copy_file ${lyricsWidgetPluginQmlFile} "$plugins_dir/lyricsWidget/LyricsWidget.qml"

        plugin_settings=${lib.escapeShellArg "${homeDirectory}/.config/DankMaterialShell/plugin_settings.json"}
        mkdir -p "$(dirname "$plugin_settings")"
        if [ -s "$plugin_settings" ]; then
          ${pkgs.jq}/bin/jq '.lyricsWidget = ((.lyricsWidget // {}) + { enabled: true })' \
            "$plugin_settings" > "$plugin_settings.tmp"
        else
          ${pkgs.jq}/bin/jq -n '{ lyricsWidget: { enabled: true } }' > "$plugin_settings.tmp"
        fi
        install -m 0644 "$plugin_settings.tmp" "$plugin_settings"
        rm -f "$plugin_settings.tmp"

        settings=${lib.escapeShellArg "${homeDirectory}/.config/DankMaterialShell/settings.json"}
        if [ -s "$settings" ]; then
          ${pkgs.jq}/bin/jq '
            .barConfigs = ((.barConfigs // []) | map(
              if .id == "default" then
                .rightWidgets = ((.rightWidgets // []) as $widgets |
                  if any($widgets[]?; .id == "lyricsWidget") then
                    $widgets
                  elif any($widgets[]?; .id == "voxtypeWidget") then
                    reduce $widgets[] as $widget ([];
                      . + [$widget] + (if $widget.id == "voxtypeWidget" then [{ id: "lyricsWidget", enabled: true }] else [] end)
                    )
                  else
                    [{ id: "lyricsWidget", enabled: true }] + $widgets
                  end
                )
              else
                .
              end
            ))
          ' "$settings" > "$settings.tmp"
          install -m 0644 "$settings.tmp" "$settings"
          rm -f "$settings.tmp"
        fi
      '';
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
              # place locally shipped plugins directly into that live tree as well
              # as through activation-managed user files below. This keeps them
              # visible in DMS's plugin picker immediately after rebuild/reboot.
              install_plugin_file() {
                local dir="$1" source="$2" name="$3"
                install -D -m 0644 "$source" "${homeDirectory}/$dir/$name"
                chown ${user}:users "${homeDirectory}/$dir/$name"
              }

              install_plugin_file "${idleInhibitPluginDir}" ${./dank-material-shell/idle-inhibit/plugin.json} plugin.json
              install_plugin_file "${idleInhibitPluginDir}" ${idleInhibitPluginQmlFile} IdleInhibitWidget.qml
              install_plugin_file "${toggleLidInhibitPluginDir}" ${./dank-material-shell/toggle-lid-inhibit/plugin.json} plugin.json
              install_plugin_file "${toggleLidInhibitPluginDir}" ${toggleLidInhibitPluginQmlFile} ToggleLidInhibitWidget.qml
              install_plugin_file "${voxtypeWidgetPluginDir}" ${./dank-material-shell/voxtype-widget/plugin.json} plugin.json
              install_plugin_file "${voxtypeWidgetPluginDir}" ${voxtypeWidgetPluginQmlFile} VoxtypeWidget.qml
              install_plugin_file "${lyricsWidgetPluginDir}" ${./dank-material-shell/lyrics-widget/plugin.json} plugin.json
              install_plugin_file "${lyricsWidgetPluginDir}" ${lyricsWidgetPluginQmlFile} LyricsWidget.qml

              PLUGIN_SETTINGS="${homeDirectory}/.config/DankMaterialShell/plugin_settings.json"
              if [ -s "$PLUGIN_SETTINGS" ]; then
                ${pkgs.jq}/bin/jq '.lyricsWidget = ((.lyricsWidget // {}) + { enabled: true })' \
                  "$PLUGIN_SETTINGS" > "$PLUGIN_SETTINGS.tmp"
              else
                ${pkgs.jq}/bin/jq -n '{ lyricsWidget: { enabled: true } }' > "$PLUGIN_SETTINGS.tmp"
              fi
              install -m 0644 "$PLUGIN_SETTINGS.tmp" "$PLUGIN_SETTINGS"
              rm -f "$PLUGIN_SETTINGS.tmp"
              chown ${user}:users "$PLUGIN_SETTINGS"

              SETTINGS="${homeDirectory}/.config/DankMaterialShell/settings.json"
              if [ -s "$SETTINGS" ]; then
                ${pkgs.jq}/bin/jq '
                  .barConfigs = ((.barConfigs // []) | map(
                    if .id == "default" then
                      .rightWidgets = ((.rightWidgets // []) as $widgets |
                        if any($widgets[]?; .id == "lyricsWidget") then
                          $widgets
                        elif any($widgets[]?; .id == "voxtypeWidget") then
                          reduce $widgets[] as $widget ([];
                            . + [$widget] + (if $widget.id == "voxtypeWidget" then [{ id: "lyricsWidget", enabled: true }] else [] end)
                          )
                        else
                          [{ id: "lyricsWidget", enabled: true }] + $widgets
                        end
                      )
                    else
                      .
                    end
                  ))
                ' "$SETTINGS" > "$SETTINGS.tmp"
                install -m 0644 "$SETTINGS.tmp" "$SETTINGS"
                rm -f "$SETTINGS.tmp"
                chown ${user}:users "$SETTINGS"
              fi
            '';
          deps = [
            "users"
            "specialfs"
          ];
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

        # Install local DMS plugins declaratively as system plugins too. User
        # plugin copies remain below for edit/debug priority, but /etc/xdg makes
        # the widgets reappear even if the persisted user plugin directory is
        # deleted before a rebuild. Source:
        # https://github.com/AvengeMedia/DankMaterialShell/blob/eb5afcdc40ea5446c27e18552ff4a19f9daf9484/quickshell/Services/PluginService.qml#L21-L29
        environment.etc = {
          "xdg/DankMaterialShell/plugins/idleInhibit/plugin.json".source =
            ./dank-material-shell/idle-inhibit/plugin.json;
          "xdg/DankMaterialShell/plugins/idleInhibit/IdleInhibitWidget.qml".source = idleInhibitPluginQmlFile;
          "xdg/DankMaterialShell/plugins/toggleLidInhibit/plugin.json".source =
            ./dank-material-shell/toggle-lid-inhibit/plugin.json;
          "xdg/DankMaterialShell/plugins/toggleLidInhibit/ToggleLidInhibitWidget.qml".source =
            toggleLidInhibitPluginQmlFile;
          "xdg/DankMaterialShell/plugins/voxtypeWidget/plugin.json".source =
            ./dank-material-shell/voxtype-widget/plugin.json;
          "xdg/DankMaterialShell/plugins/voxtypeWidget/VoxtypeWidget.qml".source = voxtypeWidgetPluginQmlFile;
          "xdg/DankMaterialShell/plugins/lyricsWidget/plugin.json".source =
            ./dank-material-shell/lyrics-widget/plugin.json;
          "xdg/DankMaterialShell/plugins/lyricsWidget/LyricsWidget.qml".source = lyricsWidgetPluginQmlFile;
        };

        # DMS registry themes are loaded from <theme>/theme.json; generating only
        # that required file keeps previews optional while making the palette
        # reproducible from modules/theme.nix. Source:
        # https://github.com/AvengeMedia/DankMaterialShell/blob/eb5afcdc40ea5446c27e18552ff4a19f9daf9484/docs/CUSTOM_THEMES.md#theme-structure
        system.activationScripts.dank-material-shell-user-files = {
          text =
            self.lib.userFiles.mkActivationScript {
              inherit user homeDirectory;
              inherit pkgs;
              files = {
                ${dmsThemeFile} = {
                  text = builtins.toJSON dmsTheme;
                  type = "copy";
                };
                ${voxtypeConfigFile}.text = voxtypeConfig;
              };
            }
            + ''
              ${localDmsPluginsInstaller}
              chown -R ${user}:users \
                "${homeDirectory}/.config/DankMaterialShell/plugins" \
                "${homeDirectory}/.config/DankMaterialShell/plugin_settings.json" \
                "${homeDirectory}/.config/DankMaterialShell/settings.json" \
                2>/dev/null || true
            '';
          # Run after the impermanence bind mounts exist; otherwise boot-time
          # activation writes into the hidden pre-mount ~/.config tree and DMS
          # sees stale persisted files such as GC-collected theme symlinks.
          deps = [
            "users"
            "specialfs"
          ];
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
            ExecStartPre = "${localDmsPluginsInstaller}";
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
