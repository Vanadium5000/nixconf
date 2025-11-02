pkgs: {
  # https://github.com/ashish-kus/waybar-minimal/blob/main/src/config.jsonc
  # Options: https://github.com/Alexays/Waybar/wiki/Configuration
  backlight = {
    device = "intel_backlight";
    format = "󰖨 {percent}%";
    on-scroll-down = "brightness-down";
    on-scroll-up = "brightness-up";
  };
  "backlight/slider" = {
    min = 0;
    max = 100;
    orientation = "horizontal";
    device = "intel_backlight";
  };
  "group/blight" = {
    orientation = "horizontal";
    drawer = {
      transition-duration = 500;
      transition-left-to-right = false;
    };
    modules = [
      "backlight"
      "backlight/slider"
    ];
  };
  battery = {
    interval = 5;
    states = {
      good = 95;
      warning = 30;
      critical = 20;
    };
    tooltip = "{time}";
    format = "{icon} {capacity}%";
    format-time = "{H}h {M}min";
    format-charging = "{icon} {capacity}%";
    format-plugged = "󰠠 {capacity}%";
    format-icons = [
      "󰁺"
      "󰁻"
      "󰁼"
      "󰁼"
      "󰁽"
      "󰁾"
      "󰁿"
      "󰂁"
      "󰂂"
      "󰁹"
    ];
    on-click = "rofi-powermenu";
  };
  "group/system" = {
    orientation = "horizontal";
    modules = [
      "group/audio"
      "group/blight"
      "battery"
    ];
  };
  "custom/recording" = {
    return-type = "json";
    format = "{icon}{text}";
    format-icons = {
      recording-active = "󰻃 ";
      #recording-inactive = "󰑊 ";
    };
    hide-empty-text = true;
    exec-if = "which waybar-is-recording";
    exec = "waybar-is-recording";
    on-click = "stop-recording";
  };
}
