pkgs: self:
let
  colorpicker = pkgs.writeShellScriptBin "colorpicker" ''
    check() {
      command -v "$1" 1>/dev/null
    }

    notify() {
      check notify-send && {
        notify-send -a "Color Picker" "$@"
        return
      }
      echo "$@"
    }

    loc="$HOME/.cache/colorpicker"
    [ -d "$loc" ] || mkdir -p "$loc"
    [ -f "$loc/colors" ] || touch "$loc/colors"

    limit=10

    [[ $# -eq 1 && $1 = "-l" ]] && {
      cat "$loc/colors"
      exit
    }

    [[ $# -eq 1 && $1 = "-j" ]] && {
      text="$(head -n 1 "$loc/colors")"

      mapfile -t allcolors < <(tail -n +2 "$loc/colors")
      # allcolors=($(tail -n +2 "$loc/colors"))
      tooltip="<b>   COLORS</b>\n\n"

      tooltip+="-> <b>$text</b>  <span color='$text'></span>  \n"
      for i in "''${allcolors[@]}"; do
        tooltip+="   <b>$i</b>  <span color='$i'></span>  \n"
      done

      cat <<EOF
    { "text":"󰈊", "tooltip":"$tooltip"}
    EOF

      exit
    }

    check hyprpicker || {
      notify "hyprpicker is not installed"
      exit
    }
    killall -q hyprpicker
    color=$(hyprpicker)

    check wl-copy && {
      echo "$color" | sed -z 's/\n//g' | wl-copy --type text/plain
    }

    prevColors=$(head -n $((limit - 1)) "$loc/colors")
    echo "$color" >"$loc/colors"
    echo "$prevColors" >>"$loc/colors"
    sed -i '/^$/d' "$loc/colors"
    pkill -RTMIN+1 waybar
  '';
in
{
  # https://github.com/ashish-kus/waybar-minimal/blob/main/src/config.jsonc
  # Options: https://github.com/Alexays/Waybar/wiki/Configuration
  "custom/dictation" = {
    exec = "${pkgs.writeShellScript "dictation-waybar" ''
      status=$(dictation status 2>/dev/null)
      if [ -z "$status" ]; then
        echo '{"text":"","class":"inactive","tooltip":"Dictation unavailable"}'
        exit 0
      fi
      active=$(echo "$status" | ${pkgs.jq}/bin/jq -r '.active // false')
      mode=$(echo "$status" | ${pkgs.jq}/bin/jq -r '.mode // "idle"')
      text=$(echo "$status" | ${pkgs.jq}/bin/jq -r '.text // ""')
      error=$(echo "$status" | ${pkgs.jq}/bin/jq -r '.error // ""')
      uptime=$(echo "$status" | ${pkgs.jq}/bin/jq -r '.uptime // 0')

      if [ "$active" = "true" ]; then
        case "$mode" in
          live) icon="🎙️" ;;
          transcribe) icon="📝" ;;
          *) icon="⏳" ;;
        esac
        tooltip="<b>$mode</b>\n$text"
        [ -n "$error" ] && tooltip="$tooltip\n<span color='#ff6b6b'>$error</span>"
        [ "$uptime" -gt 0 ] && tooltip="$tooltip\nUptime: ''${uptime}s"
        ${pkgs.jq}/bin/jq -nc --arg t "$icon" --arg c "active" --arg tip "$tooltip" '{text:$t,class:$c,tooltip:$tip}'
      else
        ${pkgs.jq}/bin/jq -nc '{text:"",class:"inactive",tooltip:"Click to start dictation"}'
      fi
    ''}";
    return-type = "json";
    interval = 1;
    format = "{}";
    on-click = "dictation toggle";
    tooltip = true;
  };
  "custom/notifications" = {
    format = "󰂚 {}";
    exec = "qs-notifications count 2>/dev/null || echo 0";
    on-click = "qs-notifications toggle";
    interval = 1;
    tooltip = false;
  };
  "custom/logo" = {
    "format" = " ";
    "on-click" = "qs-launcher";
    "tooltip" = false;
  };
  "custom/weather" = {
    format = "{}°";
    tooltip = true;
    interval = 600;
    exec = "${pkgs.wttrbar}/bin/wttrbar";
    return-type = "json";
  };
  "custom/nvidia" = {
    exec = "nvidia-smi --query-gpu=utilization.gpu,temperature.gpu --format=csv,nounits,noheader | sed 's/\\([0-9]\\+\\), \\([0-9]\\+\\)/\\1% 🌡️\\2°C/g'";
    format = "{} 🖥️";
    interval = 2;
  };
  "custom/clipboard" = {
    "format" = "󰅍";
    "interval" = 5;
    "tooltip" = true;
    "on-click" = "sh -c 'cliphist list | qs-dmenu -p Clipboard | cliphist decode | wl-copy --type text/plain'";
  };
  "custom/nightshift" = {
    exec = "night-shift-status-icon";
    interval = 10;
    tooltip = true;
    on-click = "night-shift";
  };
  "custom/colorpicker" = {
    format = "{}";
    return-type = "json";
    tooltip = true;
    interval = "once";
    exec = "${colorpicker}/bin/colorpicker -j";
    on-click = "${colorpicker}/bin/colorpicker";
  };
  "custom/lid-inhibit" = {
    format = "{}";
    return-type = "json";
    exec = "${self.packages.${pkgs.stdenv.hostPlatform.system}.lid-status}/bin/lid-status";
    on-click = "${
      self.packages.${pkgs.stdenv.hostPlatform.system}.toggle-lid-inhibit
    }/bin/toggle-lid-inhibit";
    interval = 2;
    tooltip = false;
  };
  "group/actions" = {
    orientation = "horizontal";
    modules = [
      "custom/clipboard"
      "idle_inhibitor"
      "custom/lid-inhibit"
      "custom/dictation"
      # "custom/nightshift"
      "custom/colorpicker"
    ];
  };
}
