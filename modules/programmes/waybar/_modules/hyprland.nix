pkgs: {
  # https://github.com/ashish-kus/waybar-minimal/blob/main/src/config.jsonc
  # Options: https://github.com/Alexays/Waybar/wiki/Configuration
  "hyprland/workspaces" = {
    # Use icons instead of numbers
    #format = "{icon}";

    format-icons = {
      default = "";
    };
    persistent-workspaces = {
      "*" = [
        1
        2
        3
        4
        5
        6
      ];
    };
  };
  "hyprland/window" = {
    format = "( {class} )";
    rewrite = {
      "(.*) - Mozilla Firefox" = "🌎 $1";
      "org.telegram.desktop" = "> [$1]";
      "org.gnome.Nautilus" = "> [$1]";
      "(.*) - zsh" = "> [$1]";
      "(.*) - fish" = "> [$1]";
    };
  };
}
