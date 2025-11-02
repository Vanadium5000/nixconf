pkgs: theme: {
  # https://github.com/ashish-kus/waybar-minimal/blob/main/src/config.jsonc
  # Options: https://github.com/Alexays/Waybar/wiki/Configuration
  idle_inhibitor = {
    format = "{icon}";
    format-icons = {
      activated = "󰾪";
      deactivated = "󰅶";
    };
  };
  tray = {
    icon-size = theme.system.font-size;
    spacing = 3;

    show-passive-items = true;
  };
  # TODO: Add CalDav support as the example shows here: https://github.com/Alexays/Waybar/wiki/Module:-Custom:-Examples#calendar-with-caldav-integration
  clock = {
    format = "󰸗 {:%a %d %b  %H:%M:%S}";
    format-alt = "{:%A, %B %d, %Y (%R)}  ";
    interval = 1;
    tooltip-format = "<tt><small>{calendar}</small></tt>";
    calendar = {
      mode = "year";
      mode-mon-col = 3;
      weeks-pos = "right";
      on-scroll = 1;
      format = {
        months = "<span color='#ffead3'><b>{}</b></span>";
        days = "<span color='#ecc6d9'><b>{}</b></span>";
        weeks = "<span color='#99ffdd'><b>W{}</b></span>";
        weekdays = "<span color='#ffcc66'><b>{}</b></span>";
        today = "<span color='#ff6699'><b><u>{}</u></b></span>";
      };
    };
    actions = {
      on-click-right = "mode";
      on-scroll-up = "shift_up";
      on-scroll-down = "shift_down";
    };
  };
}
