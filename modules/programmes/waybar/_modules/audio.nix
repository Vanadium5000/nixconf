pkgs: {
  # https=//github.com/ashish-kus/waybar-minimal/blob/main/src/config.jsonc
  # Options= https=//github.com/Alexays/Waybar/wiki/Configuration
  pulseaudio = {
    format = "{icon} {volume}%";
    format-bluetooth = "󰂰";
    format-muted = "";
    tooltip-format = "{volume}% {icon}";
    format-icons = {
      headphones = "";
      bluetooth = "󰥰";
      handsfree = "";
      headset = "󱡬";
      phone = "";
      portable = "";
      car = "";
      default = [
        "🕨"
        "🕩"
        "🕪"
      ];
    };
    scroll-step = 5;
    justify = "center";
    on-click = "amixer sset Master toggle";
    on-click-right = "pavucontrol";
    on-scroll-up = "pactl set-sink-volume @DEFAULT_SINK@ +5%";
    on-scroll-down = "pactl set-sink-volume @DEFAULT_SINK@ -5%";
  };
  "pulseaudio#mic" = {
    format = "{format_source} {volume}%";
    format-source = "";
    format-source-muted = "";
    tooltip-format = "{volume}% {format_source} ";
    on-click = "pactl set-source-mute 0 toggle";
    on-scroll-down = "pactl set-source-volume 0 -1%";
    on-scroll-up = "pactl set-source-volume 0 +1%";
  };
  "pulseaudio/slider" = {
    min = 0;
    max = 140;
    orientation = "horizontal";
  };
  "group/audio" = {
    orientation = "horizontal";
    drawer = {
      transition-duration = 500;
      transition-left-to-right = false;
    };
    modules = [
      "pulseaudio"
      "pulseaudio#mic"
      "pulseaudio/slider"
    ];
  };

  # Visualize audio using cava
  cava = {
    format = "{bars}";
    format_silent = "quiet";
    bars = 14;
    bar_delimiter = 0;
    hide_on_silence = true;
    format-icons = [
      "▁"
      "▂"
      "▃"
      "▄"
      "▅"
      "▆"
      "▇"
      "█"
    ];

    method = "pipewire";
    actions = {
      on-click-right = "mode";
    };
  };
}
