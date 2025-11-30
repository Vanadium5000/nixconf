pkgs:
let
  powerdraw = pkgs.writeShellScriptBin "powerdraw" ''
    # Find the battery file (BAT0 or BAT1 etc.)
    bat_path=$(echo /sys/class/power_supply/BAT*/power_now)

    powerDraw=""
    if [ -f "$bat_path" ]; then
      # Read µW, convert to W (integer division)
      micro_watts=$(cat "$bat_path")
      watts=$(( micro_watts / 1000000 ))
      powerDraw="''${watts}w"
    fi

    # Check if empty or numerically zero
    if [ -z "$powerDraw" ] || [ "$watts" -eq 0 ]; then
      echo "{\"text\":\"\", \"tooltip\":\"power Draw 󱐥 ''${powerDraw}\"}"
      exit 0
    fi

    echo "{\"text\":\"󱐥 ''${powerDraw}\", \"tooltip\":\"power Draw 󱐥 ''${powerDraw}\"}"
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
