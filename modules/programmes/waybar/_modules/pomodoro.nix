pkgs: {
  "custom/pomodoro" = {
    exec = "${pkgs.pomodoro-for-waybar}/bin/pomodoro-for-waybar";
    return-type = "json";
    interval = 1;
    format = "{}";
    on-click = "${pkgs.pomodoro-for-waybar}/bin/pomodoro-for-waybar toggle";
    on-click-right = "${pkgs.pomodoro-for-waybar}/bin/pomodoro-for-waybar skip";
    on-click-middle = "${pkgs.pomodoro-for-waybar}/bin/pomodoro-for-waybar reset";
  };
}
