pkgs: {
  # https://github.com/ashish-kus/waybar-minimal/blob/main/src/config.jsonc
  # Options: https://github.com/Alexays/Waybar/wiki/Configuration
  "custom/notifications" = {
    format = "󰂚 {}";
    exec = "swaync-client --count";
    on-click = "swaync-client -t";
    interval = 1;
  };
  "custom/logo" = {
    "format" = " ";
    "on-click" = "rofi-menu";
    "tooltip" = false;
  };
  "custom/weather" = {
    format = "{}°";
    tooltip = true;
    interval = 600;
    exec = "${pkgs.wttrbar}/bin/wttrbar";
    return-type = "json";
  };
  "custom/nvidia" = {
    exec = "nvidia-smi --query-gpu=utilization.gpu,temperature.gpu --format=csv,nounits,noheader | sed 's/\\([0-9]\\+\\), \\([0-9]\\+\\)/\\1% 🌡️\\2°C/g'";
    format = "{} 🖥️";
    interval = 2;
  };
  "custom/clipboard" = {
    format = "󰅍";
    interval = 5;
    tooltip = true;
    on-click = "sh -c 'cliphist list | rofi -dmenu | cliphist decode | wl-copy'";
  };
  "custom/nightshift" = {
    exec = "night-shift-status-icon";
    interval = 10;
    tooltip = true;
    on-click = "night-shift";
  };
  "custom/colorpicker" = {
    format = "{}";
    return-type = "json";
    tooltip = true;
    interval = "once";
    exec = "colorpicker -j";
    on-click = "colorpicker";
  };
  "group/actions" = {
    orientation = "horizontal";
    modules = [
      "custom/clipboard"
      "idle_inhibitor"
      "custom/nightshift"
      "custom/colorpicker"
    ];
  };
}
