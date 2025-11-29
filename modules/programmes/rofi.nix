{
  self,
  inputs,
  ...
}:

{
  perSystem =
    {
      pkgs,
      ...
    }:
    let
      inherit (self) theme colors colorsRgba;

      config = pkgs.writeText "config.rasi" ''
        configuration {
          drun-display-format: "{icon} {name}";
          font: "${theme.font} Bold ${toString theme.system.font-size}";
          modi: "window,run,drun,emoji,calc,";
          show-icons: true;
          //icon-theme: "Rose Pine";
          sort: true;
          case-sensitivity: false; 
          sorting-method: "fzf";
          hide-scrollbar: false;
          terminal: "kitty";
          display-drun: "   Apps ";
          display-run: "   Run ";
          display-window: "  Window";
          display-Network: " 󰤨  Network";
          display-emoji: "  Emoji  ";
          display-calc: "  Calc";
          sidebar-mode: true;
          hover-select: true;

          steal-focus: false;
          scroll-method: 1; /* continuous (not per page) */
          normal-window: true; /* Make rofi react like a normal application window */

          run,drun {
            fallback-icon: "utilities-terminal";
          }
        }



        * {
            bg:  ${colorsRgba.background};
            bg-opaque: ${colors.background};
            fgd: ${colors.foreground};
            cya: ${colors.base0C};
            grn: ${colors.base0B};
            ora: ${colors.base09};
            pur: ${colors.base0F};
            red: ${colors.base08};
            yel: ${colors.base0A};
            acc: ${colors.accent};
            acc-alt: ${colors.accent-alt};


            foreground: @fgd;
            background: @bg;
            background-opaque: @bg-opaque;
            active-background: @acc;
            urgent-background: @red;

            selected-background: @active-background;
            selected-urgent-background: @urgent-background;
            selected-active-background: @active-background;
            separatorcolor: @active-background;
            bordercolor: ${colors.border-color};

            /* Reset all styles */
            border-radius: ${toString theme.rounding}px;
            min-height: 0;
            margin: 0;
            padding: 0px;
            padding-left: 0px;
            padding-right: 0px;
            //background: transparent;
        }

        #window {
            background-color: @background;
            border:           ${toString theme.border-size};
            border-radius: ${toString theme.rounding};
            border-color: @bordercolor;
            padding:          5;
        }
        #mainbox {
            border:  0;
            padding: 5;
        }
        #message {
            border:       ${toString theme.border-size}px dash 0px 0px ;
            border-color: @separatorcolor;
            padding:      1px ;
        }
        #textbox {
            text-color: @foreground;
        }
        #listview {
            fixed-height: 0;
            border:       ${toString theme.border-size}px dash 0px 0px ;
            border-color: @bordercolor;
            spacing:      2px ;
            scrollbar:    false;
            padding:      2px 0px 0px ;
        }
        #element {
            border:  0;
            padding: 1px ;
        }
        /* Get rid of @background (use transparent instead) for elements to avoid double opacity bad-looking ui */
        #element.normal.normal {
            background-color: transparent;
            text-color:       @foreground;
        }
        #element.normal.urgent {
            background-color: @urgent-background;
            text-color:       @urgent-foreground;
        }
        #element.normal.active {
            background-color: @active-background;
            text-color:       @background-opaque;
        }
        #element.selected.normal {
            background-color: @selected-background;
            text-color:       @background-opaque;
        }
        #element.selected.urgent {
            background-color: @selected-urgent-background;
            text-color:       @foreground;
        }
        #element.selected.active {
            background-color: @selected-active-background;
            text-color:       @background-opaque;
        }
        #element.alternate.normal {
            background-color: transparent;
            text-color:       @foreground;
        }
        #element.alternate.urgent {
            background-color: @urgent-background;
            text-color:       @foreground;
        }
        #element.alternate.active {
            background-color: @active-background;
            text-color:       @foreground;
        }
        #scrollbar {
            width:        2px ;
            border:       0;
            handle-width: 8px ;
            padding:      0;
        }
        #sidebar {
            border:       ${toString theme.border-size}px dash 0px 0px ;
            border-color: @separatorcolor;
        }
        #button.selected {
            background-color: @selected-background;
            text-color:       @background-opaque;
        }
        #inputbar {
            spacing:    0;
            text-color: @foreground;
            padding:    1px ;
        }
        #case-indicator {
            spacing:    0;
            text-color: @foreground;
        }
        #entry {
            spacing:    0;
            text-color: @cya;
        }
        #prompt {
            spacing:    0;
            text-color: @fgd;
        }
        #inputbar {
            children:   [ prompt,textbox-prompt-colon,entry,case-indicator ];
        }
        #textbox-prompt-colon {
            expand:     false;
            str:        ":";
            margin:     0px 0.3em 0em 0em ;
            text-color: @fgd;
        }
      '';

      config-images = pkgs.writeTextFile {
        name = "config-images.rasi";
        text = ''
          @import "${config}"

          /* ---- Configuration ---- */
          window {
            width: 60%;
          }

          /* ---- Imagebox ---- */
          imagebox {
            orientation: vertical;
            children:
              [ "entry", "listbox"];
          }

          /* ---- Listview ---- */
          listview {
            columns: 4;
            lines: 3;
          }

          /* ---- Element ---- */
          element {
            orientation: vertical;
            padding: 0px;
            spacing: 0px;
          }

          element-icon {
            size: 20%;
          }
        '';
      };
    in
    {
      packages.rofi = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.rofi.override {
          plugins = [
            pkgs.rofi-emoji
            pkgs.rofi-calc
          ];
        };
        flags = {
          "-config" = config;
        };
      };
      packages.rofi-images = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.rofi.override {
          plugins = [
            pkgs.rofi-emoji
            pkgs.rofi-calc
          ];
        };
        flags = {
          "-config" = config-images;
        };
      };
      packages.rofi-askpass = pkgs.writeShellScriptBin "rofi-askpass" ''
        : | rofi -dmenu \
          -sync \
          -password \
          -i \
          -no-fixed-num-lines \
          -p "Password: " \
          2> /dev/null
      '';
      packages.rofi-powermenu = pkgs.writeShellScriptBin "rofi-powermenu" ''
        options=(
          "󰌾 Lock"
          "󰍃 Logout"
          " Suspend"
          "󰑐 Reboot"
          "󰿅 Shutdown"
        )

        selected=$(printf '%s\n' "''${options[@]}" | rofi -dmenu)

        selected=''${selected:2}

        case $selected in
          "Lock")
            ${pkgs.hyprlock}/bin/hyprlock
            ;;
          "Logout")
            hyprctl dispatch exit
            ;;
          "Suspend")
            systemctl suspend
            ;;
          "Reboot")
            systemctl reboot
            ;;
          "Shutdown")
            systemctl poweroff
            ;;
        esac
      '';
    };
}
