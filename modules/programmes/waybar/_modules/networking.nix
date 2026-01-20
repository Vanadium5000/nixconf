pkgs: {
  # https://github.com/ashish-kus/waybar-minimal/blob/main/src/config.jsonc
  # Options: https://github.com/Alexays/Waybar/wiki/Configuration
  network = {
    format-wifi = " ";
    format-ethernet = "󰈀";
    format-disconnected = "󱐅";
    tooltip-format = "{ipaddr}";
    tooltip-format-wifi = "{essid} ({signalStrength}%)  | {ipaddr}";
    tooltip-format-ethernet = "{bandwidthTotalBytes}";
    on-click = "networkmanager_dmenu";
  };
  "network#speed" = {
    format = "󰇚 {bandwidthDownBits} 󰕒 {bandwidthUpBits}";
    interval = 2;
    tooltip-format = "{ipaddr}";
    tooltip-format-wifi = "{essid} ({signalStrength}%)   \n{ipaddr} | {frequency} MHz{icon} ";
    tooltip-format-ethernet = "{ifname} 󰈀 \n{ipaddr} | {frequency} MHz{icon} ";
    tooltip-format-disconnected = "Not Connected to any type of Network";
    tooltip = true;
    on-click = "networkmanager_dmenu";
  };
  "group/networking" = {
    orientation = "horizontal";
    drawer = {
      transition-duration = 500;
      transition-left-to-right = false;
    };
    modules = [
      "network"
      "network#speed"
    ];
  };
}
