pkgs:
let
  powerdraw = pkgs.writeShellScriptBin "powerdraw" ''
    #!/usr/bin/env bash

    bat_dir=$(dirname /sys/class/power_supply/BAT*/power_now 2>/dev/null)
    if [ ! -d "$bat_dir" ]; then
      echo "{\"text\":\"\", \"tooltip\":\"No battery detected\"}"
      exit 0
    fi

    read -r micro_watts < "$bat_dir/power_now"
    read -r micro_wh_now < "$bat_dir/energy_now"
    read -r micro_wh_full < "$bat_dir/energy_full"
    read -r status < "$bat_dir/status"

    # convert
    watts=$(( micro_watts / 1000000 ))
    wh_now=$(( micro_wh_now / 1000000 ))
    wh_full=$(( micro_wh_full / 1000000 ))

    # protection for 0 division
    if [ "$watts" -le 0 ]; then
      time_str="N/A"
    else
      if [ "$status" = "Discharging" ]; then
        minutes_left=$(( wh_now * 60 / watts ))
        time_str="$(printf '%dh %02dm left' $((minutes_left/60)) $((minutes_left%60)))"
      elif [ "$status" = "Charging" ]; then
        wh_needed=$(( wh_full - wh_now ))
        minutes_full=$(( wh_needed * 60 / watts ))
        time_str="$(printf '%dh %02dm to full' $((minutes_full/60)) $((minutes_full%60)))"
      else
        time_str="Fully charged"
      fi
    fi

    # Build tooltip
    tooltip="Status: $status\nPower: ''${watts}W\nBattery: ''${wh_now}Wh / ''${wh_full}Wh\nTime: $time_str"

    # Hide when on AC and battery is full and draw is 0
    if [[ "$status" = "Full" || "$status" = "Not charging" ]] && [ "$watts" -eq 0 ]; then
      echo "{\"text\":\"\", \"tooltip\":\"$tooltip\"}"
      exit 0
    fi

    # Otherwise show watts
    echo "{\"text\":\"󱐥 ''${watts}W\", \"tooltip\":\"$tooltip\"}"
  '';
in

{
  # https://github.com/ashish-kus/waybar-minimal/blob/main/src/config.jsonc
  # Options: https://github.com/Alexays/Waybar/wiki/Configuration
  disk = {
    interval = 300;
    format = " {percentage_used}%";
    path = "/";
  };
  cpu = {
    interval = 10;
    format = " {usage}%";
  };
  memory = {
    interval = 10;
    format = " {used:0.1f}G/{total:0.1f}G";
  };
  temperature = {
    format = " {temperatureC}°C";
    format-critical = " {temperatureC}°C";
    interval = 5;
    critical-threshold = 80;
    on-click = "foot btop";
  };
  "custom/powerDraw" = {
    format = "{}";
    hide-empty-text = true;
    interval = 2;
    exec = "${powerdraw}/bin/powerdraw";
    return-type = "json";
  };
  "group/monitoring" = {
    orientation = "horizontal";
    modules = [
      "cpu"
      "memory"
      #"temperature" # Not very useful
      "custom/powerDraw"
      #"network#speed"
      "custom/weather"
    ];
  };
}
