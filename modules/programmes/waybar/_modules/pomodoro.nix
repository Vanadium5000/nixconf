pkgs: self: {
  "custom/pomodoro" = {
    exec = "${self.packages.${pkgs.stdenv.hostPlatform.system}.pomodoro}/bin/pomodoro";
    return-type = "json";
    interval = 1;
    format = "{}";
    # Left click: toggle pause/resume
    on-click = "${self.packages.${pkgs.stdenv.hostPlatform.system}.pomodoro}/bin/pomodoro toggle";
    # Right click: skip to next phase
    on-click-right = "${self.packages.${pkgs.stdenv.hostPlatform.system}.pomodoro}/bin/pomodoro skip";
    # Middle click: reset timer
    on-click-middle = "${self.packages.${pkgs.stdenv.hostPlatform.system}.pomodoro}/bin/pomodoro reset";
    # Scroll up: start timer
    on-scroll-up = "${self.packages.${pkgs.stdenv.hostPlatform.system}.pomodoro}/bin/pomodoro start";
    # Scroll down: pause timer
    on-scroll-down = "${self.packages.${pkgs.stdenv.hostPlatform.system}.pomodoro}/bin/pomodoro pause";
  };
}
