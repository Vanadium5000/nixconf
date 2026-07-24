{
  flake.nixosModules.tuigreet =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      kdeEnabled = lib.attrByPath [ "preferences" "kde" "enable" ] false config;
    in
    {
      config = lib.mkIf (!kdeEnabled) {
        services.greetd = {
          enable = true;
          settings = {
            default_session = {
              command = "${pkgs.tuigreet}/bin/tuigreet --cmd 'uwsm start -e -D Hyprland hyprland.desktop' --remember --asterisks --container-padding 2 --time --time-format '%I:%M %p | %a • %h | %F'";
              user = "greeter";
            };
          };
        };

        environment.systemPackages = with pkgs; [
          tuigreet
          uwsm
        ];

        # this is a life saver.
        # literally no documentation about this anywhere.
        # might be good to write about this...
        # https://www.reddit.com/r/NixOS/comments/u0cdpi/tuigreet_with_xmonad_how/
        systemd.services.greetd.serviceConfig = {
          Type = "idle";
          StandardInput = "tty";
          StandardOutput = "tty";
          StandardError = "journal"; # Without this errors will spam on screen
          # Without these bootlogs will spam on screen
          TTYReset = true;
          TTYVHangup = true;
          TTYVTDisallocate = true;
        };
      };
    };
}
