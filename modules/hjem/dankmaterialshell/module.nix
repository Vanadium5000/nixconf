# Converted from the existing home-manager module
{
  flake.nixosModules.extra_hjem =
    {
      self,
      config,
      pkgs,
      lib,
      ...
    }:
    let
      # Derive user and home directory from config
      user = config.preferences.user.username;

      # JSON format helper
      jsonFormat = pkgs.formats.json { };

      # Shorthand for cfg
      cfg = config.home.programs.dankMaterialShell;
    in
    {
      # Preserve compatibility with removed/renamed options
      imports = [
        (lib.mkRemovedOptionModule [
          "programs"
          "dankMaterialShell"
          "enableNightMode"
        ] "Night mode is now always available.")
        (lib.mkRenamedOptionModule
          [ "programs" "dankMaterialShell" "enableSystemd" ]
          [ "programs" "dankMaterialShell" "systemd" "enable" ]
        )
      ];

      # Define options (kept similar to original, but now under programs.*)
      options.home.programs.dankMaterialShell = with lib.types; {
        enable = lib.mkEnableOption "DankMaterialShell";

        systemd = {
          enable = lib.mkEnableOption "DankMaterialShell systemd startup";
          restartIfChanged = lib.mkOption {
            type = bool;
            default = true;
            description = "Auto-restart dms.service when dankMaterialShell changes";
          };
        };

        enableSystemMonitoring = lib.mkOption {
          type = bool;
          default = true;
          description = "Add needed dependencies to use system monitoring widgets";
        };

        enableClipboard = lib.mkOption {
          type = bool;
          default = true;
          description = "Add needed dependencies to use the clipboard widget";
        };

        enableVPN = lib.mkOption {
          type = bool;
          default = true;
          description = "Add needed dependencies to use the VPN widget";
        };

        enableBrightnessControl = lib.mkOption {
          type = bool;
          default = true;
          description = "Add needed dependencies to have brightness/backlight support";
        };

        enableColorPicker = lib.mkOption {
          type = bool;
          default = true;
          description = "Add needed dependencies to have color picking support";
        };

        enableDynamicTheming = lib.mkOption {
          type = bool;
          default = true;
          description = "Add needed dependencies to have dynamic theming support";
        };

        enableAudioWavelength = lib.mkOption {
          type = bool;
          default = true;
          description = "Add needed dependencies to have audio wavelength support";
        };

        enableCalendarEvents = lib.mkOption {
          type = bool;
          default = true;
          description = "Add calendar events support via khal";
        };

        enableSystemSound = lib.mkOption {
          type = bool;
          default = true;
          description = "Add needed dependencies to have system sound support";
        };

        quickshell = {
          package = lib.mkPackageOption pkgs "quickshell" { };
        };

        default = {
          settings = lib.mkOption {
            type = jsonFormat.type;
            default = { };
            description = "The default settings are only read if the settings.json file doesn't exist";
          };

          session = lib.mkOption {
            type = jsonFormat.type;
            default = { };
            description = "The default session is only read if the session.json file doesn't exist";
          };
        };

        plugins = lib.mkOption {
          type = attrsOf (
            types.submodule (
              { ... }:
              {
                options = {
                  enable = lib.mkOption {
                    type = types.bool;
                    default = true;
                    description = "Whether to link this plugin";
                  };
                  src = lib.mkOption {
                    type = types.path;
                    description = "Source to link to DMS plugins directory";
                  };
                };
              }
            )
          );
          default = { };
          description = "DMS Plugins to install";
        };
      };

      # Apply configuration if enabled
      config = lib.mkIf cfg.enable {
        # Packages: core + quickshell + conditionals
        environment.systemPackages = [
          cfg.quickshell.package
          pkgs.material-symbols
          pkgs.inter
          pkgs.fira-code
          pkgs.ddcutil
          pkgs.libsForQt5.qt5ct
          pkgs.kdePackages.qt6ct
          self.packages.${pkgs.system}.dmsCli
        ]
        ++ lib.optional cfg.enableSystemMonitoring self.packages.${pkgs.system}.dgop
        ++ lib.optionals cfg.enableClipboard [
          pkgs.cliphist
          pkgs.wl-clipboard
        ]
        ++ lib.optionals cfg.enableVPN [
          pkgs.glib
          pkgs.networkmanager
        ]
        ++ lib.optional cfg.enableBrightnessControl pkgs.brightnessctl
        ++ lib.optional cfg.enableColorPicker pkgs.hyprpicker
        ++ lib.optional cfg.enableDynamicTheming pkgs.matugen
        ++ lib.optional cfg.enableAudioWavelength pkgs.cava
        ++ lib.optional cfg.enableCalendarEvents pkgs.khal
        ++ lib.optional cfg.enableSystemSound pkgs.kdePackages.qtmultimedia;

        hjem.users.${user} = {
          # Files: quickshell config, defaults, plugins, and systemd service
          files = lib.mkMerge [
            # Quickshell configuration directory (assuming source handles dirs)
            {
              ".config/quickshell/dms".source = "${
                self.packages.${pkgs.system}.dankMaterialShell
              }/etc/xdg/quickshell/dms";
            }

            # Default session (only if not empty)
            (lib.mkIf (cfg.default.session != { }) {
              ".local/state/DankMaterialShell/default-session.json".source =
                jsonFormat.generate "default-session.json" cfg.default.session;
            })

            # Default settings (only if not empty)
            (lib.mkIf (cfg.default.settings != { }) {
              ".config/DankMaterialShell/default-settings.json".source =
                jsonFormat.generate "default-settings.json" cfg.default.settings;
            })

            # Plugins (filtered by enable)
            (lib.mapAttrs' (
              name: plugin:
              lib.mkIf plugin.enable {
                name = ".config/DankMaterialShell/plugins/${name}";
                value = {
                  source = plugin.src;
                };
              }
            ) cfg.plugins)

            # Systemd service unit file (manual declaration)
            (lib.mkIf cfg.systemd.enable {
              ".config/systemd/user/dms.service".text = lib.generators.toINI { } {
                Unit = {
                  Description = "DankMaterialShell";
                  PartOf = [ "graphical-session.target" ];
                  After = [ "graphical-session.target" ];
                }
                // (lib.optionalAttrs cfg.systemd.restartIfChanged {
                  "X-Restart-Triggers" = "${self.packages.${pkgs.system}.dankMaterialShell}/etc/xdg/quickshell/dms";
                });

                Service = {
                  ExecStart = "${lib.getExe self.packages.${pkgs.system}.dmsCli} run";
                  Restart = "on-failure";
                };

                Install = {
                  WantedBy = [ "graphical-session.target" ];
                };
              };
            })
          ];
        };
      };
    };
}
