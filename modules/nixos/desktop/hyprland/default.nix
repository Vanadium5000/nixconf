{ self, ... }:
{
  flake.nixosModules.hyprland =
    {
      config,
      pkgs,
      ...
    }:
    let
      inherit (self.lib.generators) toHyprconf;
    in
    {
      services.hyprsunset.enable = true;
      services.hypridle.enable = true;
      services.hyprlock.enable = true;

      # Hypridle config
      hjem.users.${config.preferences.user.username}.files.".config/hypr/hypridle.conf".text =
        toHyprconf
          {
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

      # Add hyprpaper
      environment.systemPackages = [ pkgs.hyprpaper ];
      preferences.autostart = [ "hyprpaper" ];

      # Hyprpaper config
      hjem.users.${config.preferences.user.username}.files.".config/hypr/hyprpaper.conf".text =
        toHyprconf
          {
            attrs = {
              preload = "~/.current_wallpaper";
              wallpaper = "~/.current_wallpaper";
            };
          };
    };
}
