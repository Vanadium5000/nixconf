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
                lock_cmd = "pidof hyprlock || hyprlock"; # avoid starting multiple hyprlock instances.
                before_sleep_cmd = "loginctl lock-session"; # lock before suspend.
                after_sleep_cmd = "hyprctl dispatch dpms on"; # to avoid having to press a key twice to turn on the display.
              };

              listener = [
                {
                  timeout = 120;
                  on-timeout = "pidof hyprlock || hyprlock"; # avoid starting multiple hyprlock instances.
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
