{ inputs, ... }:
{
  perSystem =
    {
      pkgs,
      self',
      ...
    }:
    {
      packages.sound-change = inputs.wrappers.lib.wrapPackage {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "sound-change" ''
          increments="5"
          smallIncrements="1"

          case "$1" in
            mute)
              ${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
              ;;
            up)
              increment=''${2:-$increments}
              ${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ ''${increment}%+
              ;;
            down)
              increment=''${2:-$increments}
              ${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ ''${increment}%-
              ;;
            set)
              volume=''${2:-100}
              ${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ ''${volume}%
              ;;
            *)
              echo "Usage: $0 {mute|up [increment]|down [increment]|set [volume]}"
              exit 1
              ;;
          esac
        '';
      };

      packages.sound-up = inputs.wrappers.lib.wrapPackage {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "sound-up" ''
          exec ${self'.packages.sound-change}/bin/sound-change up 5
        '';
      };

      packages.sound-up-small = inputs.wrappers.lib.wrapPackage {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "sound-up-small" ''
          exec ${self'.packages.sound-change}/bin/sound-change up 1
        '';
      };

      packages.sound-down = inputs.wrappers.lib.wrapPackage {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "sound-down" ''
          exec ${self'.packages.sound-change}/bin/sound-change down 5
        '';
      };

      packages.sound-down-small = inputs.wrappers.lib.wrapPackage {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "sound-down-small" ''
          exec ${self'.packages.sound-change}/bin/sound-change down 1
        '';
      };

      packages.sound-toggle = inputs.wrappers.lib.wrapPackage {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "sound-toggle" ''
          exec ${self'.packages.sound-change}/bin/sound-change mute
        '';
      };

      packages.sound-set = inputs.wrappers.lib.wrapPackage {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "sound-set" ''
          exec ${self'.packages.sound-change}/bin/sound-change set "$1"
        '';
      };

      packages.toggle-lid-inhibit = inputs.wrappers.lib.wrapPackage {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "toggle-lid-inhibit" ''
          set -euo pipefail

          STATE_DIR="''${XDG_STATE_HOME:-$HOME/.local/state}/lid-inhibit"
          PID_FILE="$STATE_DIR/inhibitor.pid"

          mkdir -p "$STATE_DIR"

          active() {
            [[ -f "$PID_FILE" ]] || return 1

            local pid
            pid="$(<"$PID_FILE")"
            if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
              return 0
            fi

            rm -f "$PID_FILE"
            return 1
          }

          json_status() {
            if active; then
              printf '{"text":"🔓","class":"active","active":true,"tooltip":"Lid suspend inhibitor is enabled"}\n'
            else
              printf '{"text":"🔒","class":"inactive","active":false,"tooltip":"Lid suspend inhibitor is disabled"}\n'
            fi
          }

          notify() {
            ${pkgs.libnotify}/bin/notify-send "Lid Inhibit" "$1" 2>/dev/null || true
          }

          enable() {
            if active; then
              json_status
              return
            fi

            (exec ${pkgs.systemd}/bin/systemd-inhibit \
              --what=handle-lid-switch \
              --who=lid-inhibitor \
              --why="User-enabled lid-close suspend inhibition" \
              --mode=block \
              ${pkgs.coreutils}/bin/sleep infinity) &
            printf '%s\n' "$!" > "$PID_FILE"
            notify "Lid-close suspend inhibition enabled"
            json_status
          }

          disable() {
            if active; then
              kill "$(<"$PID_FILE")" 2>/dev/null || true
            fi
            rm -f "$PID_FILE"
            notify "Lid-close suspend inhibition disabled"
            json_status
          }

          case "''${1:-toggle}" in
            enable|on)
              enable
              ;;
            disable|off)
              disable
              ;;
            toggle)
              if active; then
                disable
              else
                enable
              fi
              ;;
            status|json)
              json_status
              ;;
            is-active)
              active
              ;;
            *)
              cat <<'EOF'
          Usage: toggle-lid-inhibit [enable|disable|toggle|status|is-active]

          Persistent systemd-inhibit controller for lid-close suspend inhibition.
          EOF
              exit 64
              ;;
          esac
        '';
      };

      packages.openports = inputs.wrappers.lib.wrapPackage {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "openports" ''
          set -euo pipefail

          if [[ "''${1:-}" == "--help" || "''${1:-}" == "-h" ]]; then
            cat <<'EOF'
          openports - show ports opened by the NixOS iptables firewall

          Usage:
            openports

          Reads the nixos-fw chain with `sudo iptables -L nixos-fw -v -n --line-numbers`
          and prints concise tables for explicit port openings and other NixOS firewall
          accept rules. This only inspects current iptables state; it does not modify it.
          EOF
            exit 0
          fi

          # NixOS makes sudo setuid only under /run/wrappers; the store binary
          # intentionally cannot elevate.
          SUDO="/run/wrappers/bin/sudo"
          if ! "$SUDO" -v; then
            echo "openports: sudo authentication failed" >&2
            exit 1
          fi

          "$SUDO" ${pkgs.iptables}/bin/iptables -L nixos-fw -v -n --line-numbers | ${pkgs.gawk}/bin/awk '
            NR == 1 { chain = $0; next }
            /^num[[:space:]]+/ || /^[[:space:]]*$/ { next }
            $4 != "nixos-fw-accept" { next }

            {
              extra = ""
              for (i = 11; i <= NF; i++) extra = extra (extra == "" ? "" : " ") $i
              ports = ""
              if (match(extra, /(tcp|udp) dpts?:[^ ]+/)) {
                ports = substr(extra, RSTART, RLENGTH)
                sub(/^(tcp|udp) dpt:/, "", ports)
                sub(/^(tcp|udp) dpts:/, "", ports)
              } else if (match(extra, /multiport dports [^ ]+/)) {
                ports = substr(extra, RSTART, RLENGTH)
                sub(/^multiport dports /, "", ports)
              }

              if (ports != "") {
                count++
                rows[count] = sprintf("%-4s %-5s %-13s %-10s %10s %10s %-15s %-15s %s", $1, $5, ports, $7, $2, $3, $9, $10, extra)
              }
            }
          '
        '';
      };
    };
}
