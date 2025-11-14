{
  self,
  ...
}:
{
  flake.nixosModules.hyprland =
    {
      lib,
      pkgs,
      config,
      ...
    }:
    let
      inherit (lib)
        getExe
        ;

      inherit (self) theme colorsNoHash;

      mod = "SUPER";
      shiftMod = "SUPER_SHIFT";
      terminal = self.packages.${pkgs.stdenv.hostPlatform.system}.terminal;
      systemSettings = config.preferences.system;
    in
    {
      # Persist nwg-displays diplay settings
      impermanence.home.files = [
        ".config/hypr/monitors.conf"
        ".config/hypr/workspaces.conf"
      ];

      programs.hyprland.enable = true;

      home.programs.hyprland.enable = true;
      home.programs.hyprland.settings = {
        monitor = [
          ",prefered,auto,auto"
        ];

        # Fix nwg-displays: an output management utility for sway and Hyprland
        # https://github.com/nwg-piotr/nwg-displays
        source = [
          "~/.config/hypr/monitors.conf"
          "~/.config/hypr/workspaces.conf"
        ];

        general = {
          resize_on_border = true;
          extend_border_grab_area = 6;
          hover_icon_on_border = 1;

          gaps_in = theme.gaps-in;
          gaps_out = theme.gaps-out;
          border_size = theme.border-size;
          #border_part_of_window = true;
          layout = "dwindle"; # or master

          "col.active_border" = "rgb(${colorsNoHash.border-color})";
          "col.inactive_border" = "rgb(${colorsNoHash.border-color-inactive})";
        };

        group = {
          groupbar = {
            "col.active" = "rgb(${colorsNoHash.border-color})";
            "col.inactive" = "rgb(${colorsNoHash.border-color-inactive})";
          };
          "col.border_active" = "rgb(${colorsNoHash.border-color})";
          "col.border_inactive" = "rgb(${colorsNoHash.border-color-inactive})";
        };

        #-------------------------------------------------------------
        #                      Dwindle layout
        #-------------------------------------------------------------
        dwindle = {
          #pseudotile = 0 # enable pseudotiling on dwindle
          pseudotile = "yes";
          preserve_split = "yes";
          smart_split = "no";
          special_scale_factor = 1.0;
        };

        master = {
          new_status = true;
          allow_small_split = true;
          mfact = 0.5;
        };

        gesture = [
          # Workspace swipe
          "3, horizontal, workspace"
        ];

        misc = {
          vfr = true;
          vrr = 1; # 0 | 1 | 2

          disable_hyprland_logo = true;
          disable_splash_rendering = true;
          disable_autoreload = false;

          middle_click_paste = false;

          focus_on_activate = true;
          new_window_takes_over_fullscreen = 2; # 0 | 1 | 2
        };

        windowrulev2 = [
          "float, tag:modal"
          "pin, tag:modal"
          "center, tag:modal"

          # Fix flameshot
          # https://wiki.hyprland.org/FAQ/
          "noanim, class:^(flameshot)$"
          "float, class:^(flameshot)$"
          "move 0 0, class:^(flameshot)$"
          "pin, class:^(flameshot)$"
        ];

        layerrule = [
          "noanim, launcher"
          "noanim, rofi"

          # Hyprpanel
          "noanim, ^bar-([0-9]*)$"
          "blur, ^bar-([0-9]*)$"
          "blurpopups, ^bar-([0-9]*)$"
          # Hyprpanel menus
          "noanim, ^([a-z]*)menu$"
          "blur, ^([a-z]*)menu$"
          "ignorezero, ^([a-z]*)menu$" # makes blur ignore fully transparent pixels
          #"blurpopups, ^([a-z]*)menu$"

          # Waybar
          "noanim, ^waybar$"
          "blur, ^waybar$"
          "ignorezero, ^waybar$" # makes blur ignore fully transparent pixels

          # Nwg-dock-hyprland
          "noanim, ^nwg-dock$"
          "blur, ^nwg-dock$"
          "ignorezero, ^nwg-dock$" # makes blur ignore fully transparent pixels

          # Nwg-drawer
          "noanim, ^nwg-drawer$"
          "blur, ^nwg-drawer$"
          "ignorezero, ^nwg-drawer$" # makes blur ignore fully transparent pixels

          # Rofi
          "noanim, ^rofi$"
          "blur, ^rofi$"
          "ignorezero, ^rofi$" # makes blur ignore fully transparent pixels
        ];

        input = {
          kb_layout = "gb";
          #kb_options = "caps:escape";

          follow_mouse = 1;

          sensitivity = 0.5;
          repeat_delay = 300;
          repeat_rate = 50;
          numlock_by_default = true;

          touchpad = {
            natural_scroll = true;
            clickfinger_behavior = true;
          };
        };

        #-------------------------------------------------------------
        #                       Decoration section
        #-------------------------------------------------------------
        # Inspired by https://github.com/cybergaz/hyprland_rice/blob/master/.config/hypr/hyprland.conf
        decoration = {
          rounding = theme.rounding;

          #---------------------------------------------------------
          #                         Opacity
          #---------------------------------------------------------
          active_opacity = 1.0;
          inactive_opacity = theme.opacity;
          dim_inactive = 0;
          dim_strength = 0.5;
          dim_around = 0.5;
          dim_special = 0.5;

          #---------------------------------------------------------
          #                         Shadows
          #---------------------------------------------------------
          shadow.enabled = false;

          #---------------------------------------------------------
          #                          Blur
          #---------------------------------------------------------
          blur = {
            enabled = theme.blur;
            size = 2;
            passes = 3; # more passes = more resources
            new_optimizations = true;
            vibrancy = 0.1696;
          };
        };

        # Animations
        animations = {
          enabled = false;

          # Some default animations, see https://wiki.hyprland.org/Configuring/Animations/ for more
          # bezier = "myBezier, 0.25, 0.9, 0.1, 1.02";
          # animation = [
          #   "windows, 1, 7, myBezier"
          #   "windowsOut, 1, 7, default, popin 80%"
          #   "border, 1, 10, default"
          #   "borderangle, 1, 8, default"
          #   "fade, 1, 7, default"
          #   "workspaces, 1, 3, myBezier, fade"
          # ];
        };

        bind = [
          "${mod},RETURN, exec, ${getExe terminal}"
          # "${mod},E, exec, dolphin" # Dolphin
          "${mod},B, exec, librewolf" # Librewolf
          "${mod},G, exec, xdg-open https://x.com/i/grok" # Open Grok
          "${mod},A, exec, tpkill nwg-drawer || ${
            getExe self.packages.${pkgs.stdenv.hostPlatform.system}.nwg-drawer
          }" # Toggle nwg-drawer

          "${mod},L, exec, dms ipc call lock lock" # Lock

          #"${mod},TAB, overview:toggle" # Overview (Hyprspace)

          "${mod},D, exec, pkill nwg-dock || ${
            getExe self.packages.${pkgs.stdenv.hostPlatform.system}.nwg-dock-hyprland
          }" # Toggle nwg-dock-hyprland (dock)
          "${shiftMod},D, exec, waybar-toggle" # Toggle Hyprpanel (bar)

          "${mod},Q, killactive," # Close window
          "${mod},T, togglefloating," # Toggle Floating
          "${mod},F, fullscreen" # Toggle Fullscreen
          "${mod},left, movefocus, l" # Move focus left
          "${mod},right, movefocus, r" # Move focus Right
          "${mod},up, movefocus, u" # Move focus Up
          "${mod},down, movefocus, d" # Move focus Down
          "${shiftMod},up, focusmonitor, -1" # Focus previous monitor
          "${shiftMod},down, focusmonitor, 1" # Focus next monitor
          "${shiftMod},left, layoutmsg, addmaster" # Add to master
          "${shiftMod},right, layoutmsg, removemaster" # Remove from master

          "${mod},PRINT, exec, screenshot area" # Screenshot area & copy/save
          ",PRINT, exec, screenshot monitor" # Screenshot monitor & copy/save
          "${shiftMod},PRINT, exec, screenshot area toText" # Screenshot area & copy as text

          # Menus - mainly Dank Material Shell
          "${mod},SPACE, exec, dms ipc call spotlight toggle"
          "${mod},Z, exec, dms ipc call clipboard toggle"
          "${mod},W, exec, dms ipc call dankdash wallpaper"
          "${mod},C, exec, dms ipc call spotlight toggleQuery \"=\""
          "${mod},N, exec, dms ipc call notepad toggle"
          "${mod},X, exec, dms ipc call powermenu toggle"
          "${mod},W, exec, dms ipc call processlist toggle"
          "${mod},S, exec, ${getExe pkgs.grim} -g \"$(${getExe pkgs.slurp})\" - | ${getExe pkgs.swappy} -f - | wl-copy"
          "${mod},P, exec, ${getExe self.packages.${pkgs.system}.passmenu}"

          # Screen zooming on shiftMod + mouse_scroll
          "${mod},MINUS, exec, hyprctl keyword cursor:zoom_factor $(awk \"BEGIN {print $(hyprctl getoption cursor:zoom_factor | grep 'float:' | awk '{print $2}') - 0.1}\")"
          "${mod},EQUAL, exec, hyprctl keyword cursor:zoom_factor $(awk \"BEGIN {print $(hyprctl getoption cursor:zoom_factor | grep 'float:' | awk '{print $2}') + 0.1}\")"

          # Disable middle-click, it is so annoying
          ", mouse:274, exec, "
        ]
        ++ (builtins.concatLists (
          builtins.genList (
            i:
            let
              ws = i + 1;
            in
            [
              "${mod},code:1${toString i}, workspace, ${toString ws}"
              "${mod} SHIFT,code:1${toString i}, movetoworkspace, ${toString ws}"
            ]
          ) 9
        ));

        bindm = [
          # Move/resize windows with mainMod + LMB/RMB and dragging
          "${mod}, mouse:273, resizewindow"
          "${mod},mouse:272, movewindow" # Move Window (mouse)
          "${mod},R, resizewindow" # Resize Window (mouse)
        ];

        bindl = [
          ",XF86AudioMute, exec, dms ipc call audio mute" # Toggle Mute
          "SHIFT,XF86AudioMute, exec, dms ipc call audio micmute" # Toggle Mic Mute
          ",XF86AudioPlay, exec, ${pkgs.playerctl}/bin/playerctl play-pause" # Play/Pause Song
          ",XF86AudioNext, exec, ${pkgs.playerctl}/bin/playerctl next" # Next Song
          ",XF86AudioPrev, exec, ${pkgs.playerctl}/bin/playerctl previous" # Previous Song

          # Lock when closing Lid
          ",switch:Lid Switch, exec, dms ipc call lock lock"
        ];

        bindle = [
          ",XF86AudioRaiseVolume, exec, dms ipc call audio increment 5" # Sound Up
          ",XF86AudioLowerVolume, exec, dms ipc call audio decrement 5" # Sound Down
          "SHIFT,XF86AudioRaiseVolume, exec, dms ipc call audio increment 1" # Sound Up Small
          "SHIFT,XF86AudioLowerVolume, exec, dms ipc call audio decrement 1" # Sound Down Small

          ",XF86MonBrightnessUp, exec, ${getExe pkgs.brightnessctl} set --device=${systemSettings.backlightDevice} 5%+" # Brightness Up
          ",XF86MonBrightnessDown, exec, ${getExe pkgs.brightnessctl} set --device=${systemSettings.backlightDevice} 5%-" # Brightness Down
          "SHIFT,XF86MonBrightnessUp, exec, exec, ${getExe pkgs.brightnessctl} set --device=${systemSettings.backlightDevice} 1%+" # Brightness Up Small
          "SHIFT,XF86MonBrightnessDown, exec, exec, ${getExe pkgs.brightnessctl} set --device=${systemSettings.backlightDevice} 1%-" # Brightness Down Small

          ",XF86KbdBrightnessUp, exec, ${getExe pkgs.brightnessctl} set --device=${systemSettings.keyboardBacklightDevice} 5%+" # Kbd Brightness Up
          ",XF86KbdBrightnessDown, exec, ${getExe pkgs.brightnessctl} set --device=${systemSettings.keyboardBacklightDevice} 5%-" # Kbd Brightness Down
          "SHIFT,XF86KbdBrightnessUp, exec, exec, ${getExe pkgs.brightnessctl} set --device=${systemSettings.keyboardBacklightDevice} 1%+" # Kbd Brightness Up Small
          "SHIFT,XF86KbdBrightnessDown, exec, exec, ${getExe pkgs.brightnessctl} set --device=${systemSettings.keyboardBacklightDevice} 1%-" # Kbd Brightness Down Small
        ];
      };

      environment.systemPackages = with pkgs; [
        wl-clipboard
        brightnessctl
        dconf # user-prefs

        hyprpicker # color picker

        nwg-displays # displays/outputs settings gui
        protonvpn-gui # proton vpn gui

        grim
        slurp

        networkmanagerapplet
      ];
    };
}
