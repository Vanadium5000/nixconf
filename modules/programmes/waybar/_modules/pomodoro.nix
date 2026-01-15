pkgs: {
  "custom/pomodoro" = {
    exec = "${pkgs.customPackages.pomodoro-for-waybar}/bin/pomodoro-for-waybar";
    return-type = "json";
    interval = 1;
    format = "{}";
    on-click = "${pkgs.customPackages.pomodoro-for-waybar}/bin/pomodoro-for-waybar toggle";
    on-click-right = "${pkgs.customPackages.pomodoro-for-waybar}/bin/pomodoro-for-waybar skip";
    on-click-middle = "${pkgs.customPackages.pomodoro-for-waybar}/bin/pomodoro-for-waybar reset";
  };
}
