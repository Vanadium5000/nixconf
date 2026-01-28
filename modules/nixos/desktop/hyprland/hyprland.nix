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
      inherit (lib) getExe;

      inherit (self) theme colorsNoHash;

      mod = "SUPER";
      shiftMod = "SUPER_SHIFT";
      altMod = "ALT";
      terminal = self.packages.${pkgs.stdenv.hostPlatform.system}.terminal;
      systemSettings = config.preferences.system;

      makeScript = script: builtins.toString (pkgs.writeScriptBin "script" script) + "/bin/script";

      # ═══════════════════════════════════════════════════════════════════
      # UNIFIED KEYBIND DEFINITIONS - Single source of truth
      # Each keybind has: key (hyprland format), exec, description, category
      # ═══════════════════════════════════════════════════════════════════

      # Helper to create a keybind entry
      kb = key: exec: description: category: {
        inherit
          key
          exec
          description
          category
          ;
      };

      # All keybinds defined in one place
      keybinds = {
        # ── Apps ──
        apps = [
          (kb "${mod},RETURN" "exec, ${getExe terminal}" "Open terminal" "Apps")
          (kb "${mod},B" "exec, librewolf" "Open Librewolf browser" "Apps")
          (kb "${shiftMod},B" "exec, kitty btop" "Open btop (system monitor)" "Apps")
          (kb "${mod},G" "exec, xdg-open https://x.com/i/grok" "Open Grok AI" "Apps")
          (kb "${mod},L" "exec, hyprlock" "Lock screen" "Apps")
        ];

        # ── Windows ──
        windows = [
          (kb "${mod},Q" "killactive," "Close active window" "Windows")
          (kb "${altMod},T" "togglefloating," "Toggle floating mode" "Windows")
          (kb "${mod},F" "fullscreen" "Toggle fullscreen" "Windows")
          (kb "${mod},left" "movefocus, l" "Focus window left" "Windows")
          (kb "${mod},right" "movefocus, r" "Focus window right" "Windows")
          (kb "${mod},up" "movefocus, u" "Focus window up" "Windows")
          (kb "${mod},down" "movefocus, d" "Focus window down" "Windows")
          (kb "${shiftMod},up" "focusmonitor, -1" "Focus previous monitor" "Windows")
          (kb "${shiftMod},down" "focusmonitor, 1" "Focus next monitor" "Windows")
          (kb "${shiftMod},left" "layoutmsg, addmaster" "Add window to master" "Windows")
          (kb "${shiftMod},right" "layoutmsg, removemaster" "Remove window from master" "Windows")
        ];

        # ── Menus ──
        menus = [
          (kb "${mod},D" "exec, qs-dock" "Toggle dock" "Menus")
          (kb "${shiftMod},D" "exec, pkill waybar || ${
            getExe self.packages.${pkgs.stdenv.hostPlatform.system}.waybar
          }" "Toggle waybar" "Menus")
          (kb "${mod},SPACE" "exec, ${
            getExe self.packages.${pkgs.stdenv.hostPlatform.system}.qs-launcher
          }" "App launcher" "Menus")
          (kb "${mod},E" "exec, ${
            getExe self.packages.${pkgs.stdenv.hostPlatform.system}.qs-emoji
          }" "Emoji picker" "Menus")
          (kb "${mod},N" "exec, ${
            getExe self.packages.${pkgs.stdenv.hostPlatform.system}.qs-nerd
          }" "Nerd font icons picker" "Menus")
          (kb "${mod},Z"
            "exec, ${pkgs.cliphist}/bin/cliphist list | ${
              getExe self.packages.${pkgs.stdenv.hostPlatform.system}.qs-dmenu
            } -p 'Clipboard' | ${pkgs.cliphist}/bin/cliphist decode | wl-copy --type text/plain"
            "Clipboard history"
            "Menus"
          )
          (kb "${mod},W" "exec, ${
            getExe self.packages.${pkgs.stdenv.hostPlatform.system}.qs-wallpaper
          }" "Wallpaper selector" "Menus")
          (kb "${mod},P" "exec, ${
            getExe self.packages.${pkgs.stdenv.hostPlatform.system}.qs-passmenu
          }" "Password manager" "Menus")
          (kb "${shiftMod},P" "exec, ${
            getExe self.packages.${pkgs.stdenv.hostPlatform.system}.qs-passmenu
          } -a" "Password manager (autotype)" "Menus")
          (kb "${mod},M" "exec, ${
            getExe self.packages.${pkgs.stdenv.hostPlatform.system}.qs-music-search
          }" "Music search (YouTube)" "Menus")
          (kb "${altMod},M" "exec, ${
            getExe self.packages.${pkgs.stdenv.hostPlatform.system}.qs-music-local
          }" "Music search (local)" "Menus")
          (kb "${shiftMod},M"
            "exec, mpc status | grep -q 'playing' && mpc stop || { mpc clear && mpc add / && mpc shuffle && mpc play; }"
            "Toggle shuffle all / stop"
            "Menus"
          )
          (kb "${mod},C" "exec, ${
            getExe self.packages.${pkgs.stdenv.hostPlatform.system}.qs-checklist
          }" "Checklist" "Menus")
          (kb "${mod},X" "exec, ${
            getExe self.packages.${pkgs.stdenv.hostPlatform.system}.qs-powermenu
          }" "Power menu" "Menus")
          (kb "${mod},V" "exec, qs-tools" "Tools menu" "Menus")
        ];

        # ── Tools ──
        tools = [
          (kb "${shiftMod},V" "exec, stop-autoclickers" "Stop all autoclickers" "Tools")
          (kb "${altMod},V" "exec, ${
            getExe self.packages.${pkgs.stdenv.hostPlatform.system}.toggle-pause-autoclickers
          }" "Toggle pause autoclickers" "Tools")
          (kb "${shiftMod},Z" "exec, ${
            getExe self.packages.${pkgs.stdenv.hostPlatform.system}.qs-vpn
          }" "VPN selector" "Tools")
        ];

        # ── Accessibility ──
        accessibility = [
          (kb "${mod},T" "exec, dictation toggle" "Toggle dictation" "Accessibility")
          (kb "${mod},MINUS"
            ''exec, hyprctl keyword cursor:zoom_factor $(awk "BEGIN {print $(hyprctl getoption cursor:zoom_factor | grep 'float:' | awk '{print $2}') - 0.1}")''
            "Zoom out"
            "Accessibility"
          )
          (kb "${mod},EQUAL"
            ''exec, hyprctl keyword cursor:zoom_factor $(awk "BEGIN {print $(hyprctl getoption cursor:zoom_factor | grep 'float:' | awk '{print $2}') + 0.1}")''
            "Zoom in"
            "Accessibility"
          )
        ];

        # ── Help ──
        help = [
          (kb "${mod},H" "exec, ${
            getExe self.packages.${pkgs.stdenv.hostPlatform.system}.qs-keybinds
          }" "Show keybind help" "Help")
        ];

        # ── Capture ──
        capture = [
          (kb "${mod},PRINT" "exec, screenshot area" "Screenshot area (save)" "Capture")
          (kb ",PRINT" "exec, screenshot monitor" "Screenshot monitor (save)" "Capture")
          (kb "${shiftMod},PRINT" "exec, screenshot area toText" "Screenshot to text (OCR)" "Capture")
          (kb "${mod},S"
            ''exec, ${getExe pkgs.grim} -g "$(${getExe pkgs.slurp} -d)" - | ${getExe pkgs.swappy} -f -''
            "Screenshot area (edit with Swappy)"
            "Capture"
          )
          (kb "${mod},R"
            ''exec, mkdir -p ~/Videos && ${getExe pkgs.wf-recorder} -g "$(${getExe pkgs.slurp} -d)" -f ~/Videos/rec_$(date +'%Y-%m-%d_%H-%M-%S').mp4''
            "Start video recording"
            "Capture"
          )
          (kb "${shiftMod},R" "exec, pkill -SIGINT wf-recorder" "Stop video recording" "Capture")
        ];

        # ── Capture (complex scripts) ──
        captureScripts = [
          {
            key = "${shiftMod},S";
            exec =
              "exec, "
              + (makeScript ''${getExe pkgs.grim} -g "$(${getExe pkgs.slurp} -d)" - | ${getExe pkgs.tesseract} - - | ${pkgs.wl-clipboard}/bin/wl-copy --type text/plain && text=$( ${pkgs.wl-clipboard}/bin/wl-paste) && if [ ''${#text} -le 120 ]; then ${getExe pkgs.libnotify} "OCR Result" "$text"; else ${getExe pkgs.libnotify} "OCR Result" "''${text:0:100}...''${text: -20}"; fi'');
            description = "OCR screenshot to clipboard";
            category = "Capture";
          }
          {
            key = "${altMod},S";
            exec =
              "exec, "
              + (makeScript ''${getExe pkgs.grim} -g "$(${getExe pkgs.slurp} -d)" - | ${pkgs.zbar}/bin/zbarimg - | sed 's/^QR-Code:[[:space:]]*//' | ${pkgs.wl-clipboard}/bin/wl-copy --type text/plain && text=$( ${pkgs.wl-clipboard}/bin/wl-paste) && if [ ''${#text} -le 120 ]; then ${getExe pkgs.libnotify} "ZBAR SCAN Result" "$text"; else ${getExe pkgs.libnotify} "ZBAR SCAN Result" "''${text:0:100}...''${text: -20}"; fi'');
            description = "QR code scan to clipboard";
            category = "Capture";
          }
        ];

        # ── Mouse bindings (bindm) ──
        mouse = [
          (kb "${mod},mouse:273" "resizewindow" "Resize window (drag)" "Windows")
          (kb "${mod},mouse:272" "movewindow" "Move window (drag)" "Windows")
        ];

        # ── Media keys (bindl - locked) ──
        media = [
          (kb ",XF86AudioMute" "exec, ${
            getExe self.packages.${pkgs.stdenv.hostPlatform.system}.sound-toggle
          }" "Toggle mute" "Media")
          (kb ",XF86AudioPlay" "exec, ${pkgs.playerctl}/bin/playerctl play-pause" "Play/Pause media" "Media")
          (kb ",XF86AudioNext" "exec, ${pkgs.playerctl}/bin/playerctl next" "Next track" "Media")
          (kb ",XF86AudioPrev" "exec, ${pkgs.playerctl}/bin/playerctl previous" "Previous track" "Media")
        ];

        # ── System (bindl - locked) ──
        system = [
          (kb ",switch:Lid Switch" "exec, hyprlock" "Lock screen on lid close" "System")
          (kb ",switch:Lid Switch" "exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 0" "Mute on lid close"
            "System"
          )
        ];

        # ── Volume (bindle - repeat) ──
        volume = [
          (kb ",XF86AudioRaiseVolume" "exec, ${
            getExe self.packages.${pkgs.stdenv.hostPlatform.system}.sound-up
          }" "Volume up" "Media")
          (kb ",XF86AudioLowerVolume" "exec, ${
            getExe self.packages.${pkgs.stdenv.hostPlatform.system}.sound-down
          }" "Volume down" "Media")
          (kb "SHIFT,XF86AudioRaiseVolume" "exec, ${
            getExe self.packages.${pkgs.stdenv.hostPlatform.system}.sound-up-small
          }" "Volume up (small)" "Media")
          (kb "SHIFT,XF86AudioLowerVolume" "exec, ${
            getExe self.packages.${pkgs.stdenv.hostPlatform.system}.sound-down-small
          }" "Volume down (small)" "Media")
        ];

        # ── Brightness (bindle - repeat) ──
        brightness = [
          (kb ",XF86MonBrightnessUp"
            "exec, ${getExe pkgs.brightnessctl} set --device=${systemSettings.backlightDevice} 5%+"
            "Screen brightness up"
            "Brightness"
          )
          (kb ",XF86MonBrightnessDown"
            "exec, ${getExe pkgs.brightnessctl} set --device=${systemSettings.backlightDevice} 5%-"
            "Screen brightness down"
            "Brightness"
          )
          (kb "SHIFT,XF86MonBrightnessUp"
            "exec, ${getExe pkgs.brightnessctl} set --device=${systemSettings.backlightDevice} 1%+"
            "Screen brightness up (small)"
            "Brightness"
          )
          (kb "SHIFT,XF86MonBrightnessDown"
            "exec, ${getExe pkgs.brightnessctl} set --device=${systemSettings.backlightDevice} 1%-"
            "Screen brightness down (small)"
            "Brightness"
          )
          (kb ",XF86KbdBrightnessUp"
            "exec, ${getExe pkgs.brightnessctl} set --device=${systemSettings.keyboardBacklightDevice} 5%+"
            "Keyboard backlight up"
            "Brightness"
          )
          (kb ",XF86KbdBrightnessDown"
            "exec, ${getExe pkgs.brightnessctl} set --device=${systemSettings.keyboardBacklightDevice} 5%-"
            "Keyboard backlight down"
            "Brightness"
          )
          (kb "SHIFT,XF86KbdBrightnessUp"
            "exec, ${getExe pkgs.brightnessctl} set --device=${systemSettings.keyboardBacklightDevice} 1%+"
            "Keyboard backlight up (small)"
            "Brightness"
          )
          (kb "SHIFT,XF86KbdBrightnessDown"
            "exec, ${getExe pkgs.brightnessctl} set --device=${systemSettings.keyboardBacklightDevice} 1%-"
            "Keyboard backlight down (small)"
            "Brightness"
          )
        ];
      };

      # Flatten all keybinds into lists for hyprland config generation
      allBindKeybinds =
        keybinds.apps
        ++ keybinds.windows
        ++ keybinds.menus
        ++ keybinds.tools
        ++ keybinds.accessibility
        ++ keybinds.help
        ++ keybinds.capture
        ++ keybinds.captureScripts;

      # Convert keybind to hyprland bind string
      toBindString = kb: "${kb.key}, ${kb.exec}";

      # Convert key from hyprland format to human-readable for help overlay
      humanizeKey =
        key:
        let
          # Replace common patterns
          replaced =
            builtins.replaceStrings
              [
                "${mod},"
                "${shiftMod},"
                "${altMod},"
                "SHIFT,"
                ",XF86"
                "XF86"
                ",switch:"
                "switch:"
                ",PRINT"
                "PRINT"
                ",mouse:"
                "mouse:"
              ]
              [
                "SUPER + "
                "SUPER + SHIFT + "
                "ALT + "
                "SHIFT + "
                ""
                ""
                ""
                "Lid "
                ""
                "Print"
                "Mouse "
                "Mouse "
              ]
              key;
        in
        builtins.replaceStrings
          [
            "left"
            "right"
            "up"
            "down"
            "RETURN"
            "MINUS"
            "EQUAL"
          ]
          [
            "←"
            "→"
            "↑"
            "↓"
            "Return"
            "-"
            "="
          ]
          replaced;

      # Generate keybindDescriptions from unified keybinds
      allKeybindDescriptions =
        let
          allKbs =
            allBindKeybinds
            ++ keybinds.mouse
            ++ keybinds.media
            ++ keybinds.system
            ++ keybinds.volume
            ++ keybinds.brightness;
        in
        map (kb: {
          key = humanizeKey kb.key;
          inherit (kb) description category;
        }) allKbs
        # Add workspace keybinds
        ++ [
          {
            key = "SUPER + 1-9";
            description = "Switch to workspace 1-9";
            category = "Workspaces";
          }
          {
            key = "SUPER + SHIFT + 1-9";
            description = "Move window to workspace 1-9";
            category = "Workspaces";
          }
        ];
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
        "${pkgs.kdePackages.ksystemstats}/bin/ksystemstats"
        "${pkgs.kdePackages.kactivitymanagerd}/libexec/kactivitymanagerd"
      ];

      programs.hyprland = {
        enable = true;
        withUWSM = true;
      };

      home.programs.hyprland.enable = true;

      # Keybind descriptions generated from unified keybind definitions
      home.programs.hyprland.keybindDescriptions = allKeybindDescriptions;

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
          #   "noanim, launcher"
          #   "noanim, rofi"

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

        # Keybinds generated from unified definitions
        bind =
          (map toBindString allBindKeybinds)
          ++ [
            # Disable middle-click paste
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

        # Mouse bindings generated from unified definitions
        bindm = map toBindString keybinds.mouse;

        bindr = [
          # Released bindings
        ];

        # Locked bindings generated from unified definitions
        bindl = (map toBindString keybinds.media) ++ (map toBindString keybinds.system);

        # Repeat bindings generated from unified definitions
        bindle = (map toBindString keybinds.volume) ++ (map toBindString keybinds.brightness);

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
