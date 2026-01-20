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
    on-click = "qs-powermenu";
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
    format = "{icon} {text}";
    format-icons = {
      active = "󰻃";
      # You can remove the comment below if you want it visible even when not recording
      # inactive = "󰑊 ";
    };
    escape = true;
    hide-empty-text = true;
    exec = "${pkgs.writeScript "waybar-is-recording" ''
      #!${pkgs.bash}/bin/bash
      while true; do
        # Check wf-recorder
        if pgrep -x wf-recorder >/dev/null; then
          echo '{"alt":"active","class":"active","text":"Recording"}'
        
        # Check ffmpeg AND ensure it uses screen-recording encoders
        elif pids=$(pgrep -x ffmpeg); then
          # For each PID, check its command line safely
          active=false
          for pid in $pids; do
            if ps -p "$pid" -o args= | grep -Eq '(x11grab|vaapi|nvenc|h264|hevc)'; then
              active=true
              break
            fi
          done

          if $active; then
            echo '{"alt":"active","class":"active","text":"Recording"}'
          else
            echo '{"text":""}'
          fi

        # Nothing active
        else
          echo '{"text":""}'
        fi

        sleep 1
      done
    ''}";
    on-click = "${pkgs.writeScript "stop-recording" ''
      #!${pkgs.bash}/bin/bash
      if pgrep -x wf-recorder >/dev/null; then
        pkill -INT wf-recorder
        notify-send "wf-recorder" "Recording stopped"
      elif pgrep -x ffmpeg >/dev/null; then
        pkill -INT ffmpeg
        notify-send "ffmpeg" "Screen recording stopped"
      fi
    ''}";
  };
}
