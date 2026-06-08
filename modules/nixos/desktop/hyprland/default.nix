{ self, ... }:
{
  flake.nixosModules.hyprland-support =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (self.lib.generators) toHyprconf;
      hyprlandEnabled = lib.attrByPath [ "home" "programs" "hyprland" "enable" ] false config;
      currentWallpaper = "${config.preferences.paths.homeDirectory}/wallpaper/.current_wallpaper";
    in
    {
      config = lib.mkIf hyprlandEnabled {
        system.activationScripts.hyprland-support-user-files = {
          text = self.lib.userFiles.mkActivationScript {
            user = config.preferences.user.username;
            inherit pkgs;
            homeDirectory = config.preferences.paths.homeDirectory;
            files = {
              # Hypridle config
              ".config/hypr/hypridle.conf".text = toHyprconf {
                attrs = {
                  general = {
                    ignore_dbus_inhibit = false;
                    lock_cmd = "dms ipc call lock lock"; # DMS owns lock state after shell migration.
                    before_sleep_cmd = "dms ipc call lock lock"; # lock before suspend through the active shell.
                    after_sleep_cmd = "hyprctl dispatch dpms on"; # to avoid having to press a key twice to turn on the display.
                  };

                  listener = [
                    {
                      timeout = 120;
                      on-timeout = "dms ipc call lock lock"; # use the DMS lock surface instead of hyprlock.
                    }

                    {
                      timeout = 300;
                      on-timeout = "systemctl suspend";
                    }
                  ];
                };
              };

              # Hyprpaper's `wallpaper` special category is keyed by `monitor`,
              # so hyprlang requires `monitor` to be the first field in each
              # block; generic attrset rendering sorts keys and makes v0.8.4
              # abort before creating its IPC socket.
              # Source: hyprpaper v0.8.4 src/config/ConfigManager.cpp addSpecialCategory("wallpaper", key="monitor").
              ".config/hypr/hyprpaper.conf".text = ''
                wallpaper {
                  monitor =
                  path = ${currentWallpaper}
                  fit_mode = cover
                }
              '';
            };
          };
          deps = [ "users" ];
        };

        # Add hyprpaper only on hosts that actually run Hyprland.
        environment.systemPackages = [ pkgs.hyprpaper ];
        preferences.autostart = [ (lib.getExe pkgs.hyprpaper) ];
      };
    };
}
