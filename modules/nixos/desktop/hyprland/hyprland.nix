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
      altMod = "ALT";
      terminal = self.packages.${pkgs.stdenv.hostPlatform.system}.terminal;
      systemSettings = config.preferences.system;

      makeScript = script: builtins.toString (pkgs.writeScriptBin "script" script) + "/bin/script";
    in
    {
      # Persist nwg-displays diplay settings
      impermanence.home.cache.files = [
        ".config/hypr/monitors.conf"
        ".config/hypr/workspaces.conf"
      ];

      # Pesist the .current_wallpaper in wallpaper
      impermanence.home.cache.directories = [
        "wallpaper"
      ];

      # Autostart cliphist - a clipboard manager programme
      preferences.autostart = [
        "wl-paste --type text --watch ${pkgs.cliphist}/bin/cliphist store" # Stores only text data
        "wl-paste --type image --watch ${pkgs.cliphist}/bin/cliphist store" # Stores only image data
        "${pkgs.kdePackages.polkit-kde-agent-1}/libexec/polkit-kde-authentication-agent-1"
        "dictation-daemon"
      ];

      programs.hyprland = {
        enable = true;
        withUWSM = true;
      };

      home.programs.hyprland.enable = true;
      home.programs.hyprland.settings = {
        # unscale XWayland - fix rendering issues/blurry xwayland apps
        xwayland = {
          force_zero_scaling = true;
        };

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
          "${mod},B, exec, librewolf" # Librewolf
          "${shiftMod},B, exec, kitty btop" # btop - system resources
          "${mod},G, exec, xdg-open https://x.com/i/grok" # Open Grok
          # "${shiftMod},M, exec, xdg-open https://music.youtube.com" # Open YouTube Music
          "${mod},A, exec, pkill nwg-drawer || ${
            getExe self.packages.${pkgs.stdenv.hostPlatform.system}.nwg-drawer
          }" # Toggle nwg-drawer

          "${mod},L, exec, hyprlock" # Lock

          #"${mod},TAB, overview:toggle" # Overview (Hyprspace)

          "${mod},D, exec, pkill nwg-dock || ${
            getExe self.packages.${pkgs.stdenv.hostPlatform.system}.nwg-dock-hyprland
          }" # Toggle nwg-dock-hyprland (dock)
          "${shiftMod},D, exec, pkill waybar || ${
            getExe self.packages.${pkgs.stdenv.hostPlatform.system}.waybar
          }" # Toggle Hyprpanel (bar)

          "${mod},Q, killactive," # Close window
          # "${mod},T, togglefloating," # Toggle Floating (Disabled for Dictation)
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

          # Menus - mainly rofi
          "${mod},SPACE, exec, rofi -show drun" # Apps
          "${mod},E, exec, rofi -show emoji" # Emojis
          "${mod},N, exec, rofi -show nerdy" # Nerd Icons
          "${mod},Z, exec, ${pkgs.cliphist}/bin/cliphist list | rofi -dmenu -display-columns 2 | ${pkgs.cliphist}/bin/cliphist decode | wl-copy" # Clipboard manager
          "${mod},W, exec, ${getExe self.packages.${pkgs.stdenv.hostPlatform.system}.rofi-wallpaper}"
          "${mod},C, exec, rofi -show calc"
          "${mod},P, exec, ${getExe self.packages.${pkgs.stdenv.hostPlatform.system}.rofi-passmenu}"
          "${shiftMod},P, exec, ${getExe self.packages.${pkgs.stdenv.hostPlatform.system}.rofi-passmenu} -a" # With autotype
          "${mod},M, exec, ${getExe self.packages.${pkgs.stdenv.hostPlatform.system}.rofi-music-search}"
          "${shiftMod},M, exec, mpc status | grep -q 'playing' && mpc stop || { mpc clear && mpc add / && mpc shuffle && mpc play; }" # Toggle shuffle-all-play / stop
          "${mod},C, exec, ${getExe self.packages.${pkgs.stdenv.hostPlatform.system}.rofi-checklist}"
          "${mod},X, exec, rofi-powermenu"
          "${mod},V, exec, rofi-tools"
          "${shiftMod},V, exec, stop-autoclickers" # Autoclicker Safety
          "${mod},T, exec, dictation-client TOGGLE" # Dictation Toggle (More reliable than hold)
          "${shiftMod},T, exec, toggle-dictation-overlay" # Dictation Overlay
          "${altMod},V, exec, ${
            getExe self.packages.${pkgs.stdenv.hostPlatform.system}.toggle-pause-autoclickers
          }"
          # "${mod},W, exec, rofi -show processlist" # TODO: WIP

          # Recordings
          "${mod},S, exec, ${getExe pkgs.grim} -g \"$(${getExe pkgs.slurp} -d)\" - | ${getExe pkgs.swappy} -f -"
          (
            "${shiftMod},S, exec, "
            + (makeScript "${getExe pkgs.grim} -g \"$(${getExe pkgs.slurp} -d)\" - | ${getExe pkgs.tesseract} - - | ${pkgs.wl-clipboard}/bin/wl-copy && text=$( ${pkgs.wl-clipboard}/bin/wl-paste) && if [ \${#text} -le 120 ]; then ${getExe pkgs.libnotify} \"OCR Result\" \"\$text\"; else ${getExe pkgs.libnotify} \"OCR Result\" \"\${text:0:100}...\${text: -20}\"; fi")
          ) # OCR Screenshot
          (
            "${altMod},S, exec, "
            + (makeScript "${getExe pkgs.grim} -g \"$(${getExe pkgs.slurp} -d)\" - | ${pkgs.zbar}/bin/zbarimg - | sed 's/^QR-Code:[[:space:]]*//' | ${pkgs.wl-clipboard}/bin/wl-copy && text=$( ${pkgs.wl-clipboard}/bin/wl-paste) && if [ \${#text} -le 120 ]; then ${getExe pkgs.libnotify} \"ZBAR SCAN Result\" \"\$text\"; else ${getExe pkgs.libnotify} \"ZBAR SCAN Result\" \"\${text:0:100}...\${text: -20}\"; fi")
          ) # ZBAR SCAN Screenshot
          "${mod},R, exec, mkdir -p ~/Videos && ${getExe pkgs.wf-recorder} -g \"$(${getExe pkgs.slurp} -d)\" -f ~/Videos/rec_$(date +'%Y-%m-%d_%H-%M-%S').mp4" # Start video recording
          "${shiftMod},R, exec, pkill -SIGINT wf-recorder" # End video recording

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
              "${shiftMod},code:1${toString i}, movetoworkspace, ${toString ws}"
            ]
          ) 9
        ));

        bindm = [
          # Move/resize windows with mainMod + LMB/RMB and dragging
          "${mod},mouse:273, resizewindow"
          "${mod},mouse:272, movewindow" # Move Window (mouse)
          "${mod},R, resizewindow" # Resize Window (mouse)
        ];

        bindr = [
          # Released T -> Stop dictation (Removed for reliability - switched to Toggle)
          # "${mod},T, exec, dictation-client STOP"
        ];

        bindl = [
          ",XF86AudioMute, exec, ${getExe self.packages.${pkgs.stdenv.hostPlatform.system}.sound-toggle}" # Toggle Mute
          ",XF86AudioPlay, exec, ${pkgs.playerctl}/bin/playerctl play-pause" # Play/Pause Song
          ",XF86AudioNext, exec, ${pkgs.playerctl}/bin/playerctl next" # Next Song
          ",XF86AudioPrev, exec, ${pkgs.playerctl}/bin/playerctl previous" # Previous Song

          # Lock when closing Lid
          ",switch:Lid Switch, exec, hyprlock"
          ",switch:Lid Switch, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 0" # Also set volume to 0
        ];

        bindle = [
          ",XF86AudioRaiseVolume, exec, ${getExe self.packages.${pkgs.stdenv.hostPlatform.system}.sound-up}" # Sound Up
          ",XF86AudioLowerVolume, exec, ${
            getExe self.packages.${pkgs.stdenv.hostPlatform.system}.sound-down
          }" # Sound Down
          "SHIFT,XF86AudioRaiseVolume, exec, ${
            getExe self.packages.${pkgs.stdenv.hostPlatform.system}.sound-up-small
          }" # Sound Up Small
          "SHIFT,XF86AudioLowerVolume, exec, ${
            getExe self.packages.${pkgs.stdenv.hostPlatform.system}.sound-down-small
          }" # Sound Down Small

          ",XF86MonBrightnessUp, exec, ${getExe pkgs.brightnessctl} set --device=${systemSettings.backlightDevice} 5%+" # Brightness Up
          ",XF86MonBrightnessDown, exec, ${getExe pkgs.brightnessctl} set --device=${systemSettings.backlightDevice} 5%-" # Brightness Down
          "SHIFT,XF86MonBrightnessUp, exec, exec, ${getExe pkgs.brightnessctl} set --device=${systemSettings.backlightDevice} 1%+" # Brightness Up Small
          "SHIFT,XF86MonBrightnessDown, exec, exec, ${getExe pkgs.brightnessctl} set --device=${systemSettings.backlightDevice} 1%-" # Brightness Down Small

          ",XF86KbdBrightnessUp, exec, ${getExe pkgs.brightnessctl} set --device=${systemSettings.keyboardBacklightDevice} 5%+" # Kbd Brightness Up
          ",XF86KbdBrightnessDown, exec, ${getExe pkgs.brightnessctl} set --device=${systemSettings.keyboardBacklightDevice} 5%-" # Kbd Brightness Down
          "SHIFT,XF86KbdBrightnessUp, exec, exec, ${getExe pkgs.brightnessctl} set --device=${systemSettings.keyboardBacklightDevice} 1%+" # Kbd Brightness Up Small
          "SHIFT,XF86KbdBrightnessDown, exec, exec, ${getExe pkgs.brightnessctl} set --device=${systemSettings.keyboardBacklightDevice} 1%-" # Kbd Brightness Down Small
        ];
        # GUI-session Environment Variables
        env = [
          "XDG_SESSION_TYPE,wayland"
          "XDG_SESSION_DESKTOP,Hyprland"
          "XDG_CURRENT_DESKTOP,Hyprland"
          "MOZ_ENABLE_WAYLAND,1"
          "ANKI_WAYLAND,1"
          "NIXOS_OZONE_WL,1"
          "DISABLE_QT5_COMPAT,0"
          "GDK_BACKEND,wayland"
          "GDK_SCALE,2" # scaling
          "WLR_DRM_NO_ATOMIC,1"
          "QT_AUTO_SCREEN_SCALE_FACTOR,1" # enables automatic scaling
          "QT_WAYLAND_DISABLE_WINDOWDECORATION,1"
          "QT_QPA_PLATFORM,wayland"
          "WLR_BACKEND,vulkan"
          "WLR_RENDERER,vulkan"
          "WLR_NO_HARDWARE_CURSORS,1"
          "CLUTTER_BACKEND,wayland"
          "GSK_RENDERER,vulkan" # "ngl" | "vulkan"

          # Proper cursor
          "XCURSOR_THEME,Oxygen"
          "XCURSOR_SIZE,16"

          # Checklist directory
          "CHECKLIST_DIR,/home/${config.preferences.user.username}/Shared/Checklist"
        ];
      };

      environment.systemPackages = with pkgs; [
        wl-clipboard
        cliphist # Clipboard manager
        brightnessctl
        dconf # user-prefs

        hyprpolkitagent # Hyprland Polkit agent
        pkgs.kdePackages.polkit-kde-agent-1 # KDE Polkit agent

        mpc # music player controller
        playerctl # audio player controller

        quickshell # panels, widgets, etc
        wlrctl # wayland tools, e.g. autoclicking
        zbar # read qr codes
        tesseract5 # read text

        hyprpicker # color picker

        nwg-displays # displays/outputs settings gui
        protonvpn-gui # proton vpn gui

        # Utilities for eye & health protection
        hyprsunset # Blue light filter
        safeeyes # Intervalled-reminders to look around/take a break

        # Recordings
        grim
        slurp
        wf-recorder
        swappy

        networkmanagerapplet

        # Keyring
        pkgs.gnome-keyring
        pkgs.libsecret # contains secret-tool + provides the org.freedesktop.secrets service
        pkgs.seahorse # optional GUI to see/manage keyrings (very useful for debugging)
      ];

      # Enable Gnome Keyring
      services.gnome.gnome-keyring.enable = true;
    };
}
