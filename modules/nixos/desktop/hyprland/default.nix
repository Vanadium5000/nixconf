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
    in
    {
      config = lib.mkIf hyprlandEnabled {
        hjem.users.${config.preferences.user.username}.files = {
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

          # Hyprpaper config
          ".config/hypr/hyprpaper.conf".text = toHyprconf {
            attrs = {
              preload = "~/wallpaper/.current_wallpaper";
              wallpaper = ",~/wallpaper/.current_wallpaper";
            };
          };
        };

        # Add hyprpaper only on hosts that actually run Hyprland.
        environment.systemPackages = [ pkgs.hyprpaper ];
        preferences.autostart = [ "hyprpaper" ];
      };
    };
}
