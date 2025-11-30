{
  self,
  inputs,
  ...
}:

# NOTE: Waybar needs to be restarted (with hyprctl dispatch exec) each time to see changes
{
  perSystem =
    {
      pkgs,
      lib,
      ...
    }:
    let
      inherit (self) theme colors colorsRgba;

      style = pkgs.writeText "style.css" ''
        /* MYSTERIOUS CONFIG THAT CAME FROM STYLIX */
        #wireplumber,
        #pulseaudio,
        #sndio,
        #wireplumber.muted,
        #pulseaudio.muted,
        #sndio.muted,
        #upower,
        #battery,
        #upower.charging,
        #battery.Charging,
        #network,
        #network.disconnected,
        #user,
        #clock,
        #backlight,
        #cpu,
        #disk,
        #idle_inhibitor,
        #custom-lid-inhibit,
        #temperature,
        #mpd,
        #language,
        #keyboard-state,
        #memory,
        #window,
        #bluetooth,
        #bluetooth.disabled {
            padding: 0 5px;
        }
        .modules-left #workspaces button,
        .modules-center #workspaces button,
        .modules-right #workspaces button {
            border-bottom: 3px solid transparent;
        }
        .modules-left #workspaces button.focused,
        .modules-left #workspaces button.active,
        .modules-center #workspaces button.focused,
        .modules-center #workspaces button.active,
        .modules-right #workspaces button.focused,
        .modules-right #workspaces button.active {
            border-bottom: 3px solid white;
        }

        /* MY OWN CONFIG */
        * {
            /* `otf-font-awesome` is required to be installed for icons */
            font-family: '${theme.font}';
            font-size: ${toString theme.system.font-size}px;

            /* Reset all styles */
            border-radius: ${toString theme.rounding}px;
            min-height: 0;
            margin: 0;
            padding: 0px;
            padding-left: 0px;
            padding-right: 0px;
            background: transparent;
        }

        window#waybar {
            background-color: ${colorsRgba.background};
            /* color: ${colors.foreground}; */
            background-image: linear-gradient(to bottom, rgba(255,255,255,0.25)0%, rgba(0,0,0,0.5)50%, rgba(0,0,0,0.8)50%);

            border: ${toString theme.border-size}px solid ${colors.border-color};
            border-radius: ${toString theme.rounding}px;
        }

        tooltip {
          background-color: ${colorsRgba.background};
          color: white;
        }
        tooltip label {
          color: white;
        }

        /* Taskbar stuff is different to my general config */
        #taskbar {
          margin: 4px 8px;
          margin-left: 0.25cm;
          color: white;
        }
        #taskbar button {
          margin-left: 0.2cm;
          margin-right: 0.2cm;
          padding: 1px;
          border-radius: 4px;

          border-style: none;
          border-bottom-style: solid;
          border-top-style: solid;
          border-width: 1px;
          border-bottom-color: rgba(255,255,255,0.15);
          border-top-color: rgba(255,255,255,0.3);

          box-shadow: 0px 0px 4px rgba(0,0,0,0.2);
        }
        #taskbar button:hover {
          background-color: rgba(0,0,0,0);
          box-shadow: 0px 0px 5px rgba(0,0,0,0.5);
          background-image: linear-gradient(to bottom, rgba(255,255,255,0.05), rgba(0,0,0,0.4));

          border-style: none;
          border-bottom-style: solid;
          border-top-style: solid;
          border-width: 1px;
          border-bottom-color: rgba(255,255,255,0.15);
          border-top-color: rgba(255,255,255,0.3);
        }
        #taskbar button.active {
          background-image: linear-gradient(to bottom, rgba(0,255,255,0.6), rgba(0,100,100,0.1));
        }

        .modules-right {
            margin: 0 5px 0 0;
        }
        .modules-center {
            margin: 0px 0 0 0;
        }
        .modules-left {
            margin: 0 0 0 5px;
        }

        #custom-logo,
        #cava,
        #window,
        #clock,
        #monitoring, /* group */
        #actions, /* group */
        #system, /* group */
        #custom-notifications,
        #custom-recording,
        #tray,
        #network,
        #workspaces,
        #media,
        #load {
            background-image: linear-gradient(to bottom, rgba(255,255,255,0.25), rgba(0,0,0,0.025));
            box-shadow: 0px 0px 3px rgba(0,0,0,0.34);
            margin: ${toString 4}px ${toString theme.gaps-in}px ${toString 4}px ${toString theme.gaps-in}px;
            padding-left: 6px;
            padding-right: 6px;
            /* background-color: ${colors.background-alt}; */
            color: ${colors.foreground};
            /* border: ${toString theme.border-size}px solid ${colors.border-color};
            border-radius: ${toString theme.rounding}px; */

            /* Important style feature in order to give a glassy look! */
            /* I'm using the top and bottom borders to mimic highlights in highly reflective surfaces, looks good with the glassy-look */
            border-style: none;
            border-bottom-style: solid;
            border-top-style: solid;
            border-bottom-color: rgba(255,255,255,0.15);
            border-top-color: rgba(255,255,255,0.45);
            border-width: 1px;
        }

        #tray menu {
          background-color: rgba(255,255,255,0.025);
          color: rgba(220,220,220, 1);
          padding: 4px;
        }
        #tray menu menuitem {
          background-image: linear-gradient(to bottom, rgba(255,255,255,0.15),rgba(0,0,0,0.2),rgba(0,0,0,0.4));
          margin: 3px;
          color: rgb(220,220,220);
          border-radius: 4px;

          border-style: none;
          border-bottom-style: solid;
          border-top-style: solid;
          border-bottom-color: rgba(255,255,255,0.15);
          border-top-color: rgba(255,255,255,0.3);
          border-width: 1px;
        }
        #tray menu menuitem:hover {
          background-image: linear-gradient(to bottom, rgba(0,255,255,0.15), rgba(0,0,0,0.3), rgba(0,255,255,0.15));
          color: @accent_color;
          text-shadow: 0px 0px 6px @accent_color;
          box-shadow: 0px 0px 4px rgba(0,0,0,0.4);
        }

        #workspaces button {
            transition-duration: 100ms;
            all: initial;
            min-width: 0;
            color: rgb(220,220,220);
            margin-right: 0.2cm;
            margin-left: 0.2cm;
            text-shadow: 0px 0px 4px rgb(135,135,135);
        }

        /* If workspaces is the leftmost module, omit left margin */
        .modules-left > widget:first-child > #workspaces {
            margin-left: 0;
        }

        /* If workspaces is the rightmost module, omit right margin */
        .modules-right > widget:last-child > #workspaces {
            margin-right: 0;
        }

        #battery.charging, #battery.plugged {
            /* background-color: ${colorsRgba.background}; */
            color: #00FF00;
        }

        @keyframes blink {
            to {
                background-color: ${colorsRgba.background};
                color: ${colors.foreground};
            }
        }

        /* Using steps() instead of linear as a timing function to limit cpu usage */
        /* Urgent red styling for critical battery or active recording */
        #battery.critical:not(.charging), #custom-recording {
            background-color: #cc241d;
            color: ${colors.foreground};
            animation-name: blink;
            animation-duration: 0.5s;
            animation-timing-function: steps(12);
            animation-iteration-count: infinite;
            animation-direction: alternate;
        }

        #backlight-slider slider,
        #pulseaudio-slider slider {
          background: #A1BDCE;
          background-color: transparent;
          box-shadow: none;
          margin-right: 7px;
        }

        #backlight-slider trough,
        #pulseaudio-slider trough {
          margin-top: -3px;
          min-width: 90px;
          min-height: 10px;
          margin-bottom: -4px;
          border-radius: 8px;
          background: #343434;
        }

        #backlight-slider highlight,
        #pulseaudio-slider highlight {
          border-radius: 8px;
          background-color: #2096C0;
        }
      '';
      config = pkgs.writeText "config.json" (
        builtins.toJSON (
          lib.foldl' lib.recursiveUpdate { } [
            {
              # https://github.com/ashish-kus/waybar-minimal/blob/main/src/config.jsonc
              # Options: https://github.com/Alexays/Waybar/wiki/Configuration

              layer = "top";
              position = "top";
              margin-top = theme.gaps-out;
              margin-left = theme.gaps-out;
              margin-right = theme.gaps-out;

              modules-left = [
                "custom/logo"
                "hyprland/workspaces"
                "tray"
                "group/actions"
                "group/monitoring"
                "network#speed"
              ];
              modules-center = [
                "clock"
                #"custom/lyrics"
                #"cava"
              ];
              modules-right = [
                "custom/recording"
                "group/media"
                #"hyprland/window"
                "group/system"
                "custom/notifications"
              ];
            }
            # The "_" prefix makes import-tree ignore the nix files
            (import ./_modules/audio.nix pkgs)
            (import ./_modules/custom.nix pkgs self)
            (import ./_modules/general.nix pkgs theme)
            (import ./_modules/hyprland.nix pkgs)
            (import ./_modules/media.nix pkgs)
            (import ./_modules/networking.nix pkgs)
            (import ./_modules/resources.nix pkgs)
            (import ./_modules/system.nix pkgs)
          ]
        )
      );
    in
    {

      packages.waybar = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.waybar;
        flags = {
          "--config" = config;
          "--style" = style;
        };
      };
    };
}
