# Networking: prefer Cloudflare encrypted DNS, always fall back to plain/DHCP DNS.
# Captive portals and flaky hotel paths must keep working if DoT or a service fails.
# Fail-open: static public /etc/resolv.conf (not 127.0.0.53 stub). NSS uses resolved
# first when healthy; if resolved dies, glibc dns uses these nameservers directly.
# Source: man systemd-resolved.service; man nsswitch.conf; man resolved.conf
{ ... }:
{
  flake.nixosModules.common =
    {
      pkgs,
      options,
      config,
      lib,
      ...
    }:
    let
      cfg = config.preferences;
      opensnitchRule = name: description: operator: {
        inherit name description operator;
        created = "2026-07-09T00:00:00Z";
        updated = "2026-07-09T00:00:00Z";
        action = "allow";
        duration = "always";
        enabled = true;
        precedence = true;
        nolog = false;
      };
      simple = operand: data: {
        type = "simple";
        inherit operand data;
        sensitive = false;
        list = null;
      };
      regexp = operand: data: {
        type = "regexp";
        inherit operand data;
        sensitive = false;
        list = null;
      };
      network = operand: data: {
        type = "network";
        inherit operand data;
        sensitive = false;
        list = null;
      };
      list = operators: {
        type = "list";
        operand = "list";
        data = "";
        sensitive = false;
        list = operators;
      };

      # Imperative DNS recovery without a rebuild. PATH: dns-emergency.
      # Source: man systemd-resolved.service; man resolvectl; man nmcli
      dnsEmergency = pkgs.writeShellApplication {
        name = "dns-emergency";
        runtimeInputs = with pkgs; [
          coreutils
          systemd
          networkmanager
          iproute2
          gnugrep
          gawk
          gnused
          curl
        ];
        text = ''
          set -euo pipefail

          usage() {
            printf '%s\n' \
              'dns-emergency — fix DNS without a NixOS rebuild' \
              "" \
              'Usage:' \
              '  dns-emergency status' \
              '  dns-emergency restart-resolved' \
              '  dns-emergency plain' \
              '  dns-emergency dhcp' \
              '  dns-emergency disable-dot' \
              '  dns-emergency restore' \
              '  dns-emergency stop-resolved' \
              '  dns-emergency flush' \
              '  dns-emergency test [host]' \
              "" \
              'Commands:' \
              '  status             Show resolv.conf, resolved, NM DNS, probes' \
              '  restart-resolved   Restart systemd-resolved and flush caches' \
              '  plain              Static public DNS in /etc/resolv.conf' \
              '  dhcp               Write NM/DHCP nameservers into /etc/resolv.conf' \
              '  disable-dot        Runtime DNSOverTLS=no (broken middleboxes)' \
              '  restore            Restore flake default public resolv.conf + start resolved' \
              '  stop-resolved      Stop resolved so NSS falls through to /etc/resolv.conf' \
              '  flush              resolvectl flush-caches + reset-server-features' \
              '  test [host]        getent + curl probes (default: example.com)' \
              "" \
              'plain/dhcp work even if systemd-resolved is dead.' \
              'OpenSnitch may prompt on direct :53 after plain/dhcp — allow, or:' \
              '  opensnitch-bypass -- dns-emergency test'
          }

          need_root() {
            if [ "$(id -u)" -ne 0 ]; then
              echo "error: needs root — sudo dns-emergency $*" >&2
              exit 1
            fi
          }

          # Always write a real file (never leave a dead 127.0.0.53 symlink).
          write_resolv_lines() {
            local tmp
            tmp="$(mktemp)"
            printf '%s\n' "$@" >"$tmp"
            chmod 644 "$tmp"
            mv -f "$tmp" /etc/resolv.conf
            echo "wrote /etc/resolv.conf:"
            cat /etc/resolv.conf
          }

          default_public_resolv() {
            write_resolv_lines \
              "# flake default / dns-emergency restore — public DNS, no local stub" \
              "nameserver 1.1.1.1" \
              "nameserver 1.0.0.1" \
              "nameserver 9.9.9.9" \
              "nameserver 8.8.8.8" \
              "options edns0"
          }

          cmd_status() {
            echo "== /etc/resolv.conf =="
            ls -la /etc/resolv.conf 2>&1 || true
            cat /etc/resolv.conf 2>&1 || true
            echo
            echo "== resolved unit =="
            systemctl is-active systemd-resolved 2>&1 || true
            systemctl is-failed systemd-resolved 2>&1 || true
            resolvectl status 2>&1 | head -n 80 || true
            echo
            echo "== NetworkManager DNS =="
            nmcli -t -f NAME,DEVICE,TYPE,STATE connection show --active 2>&1 || true
            nmcli -g IP4.DNS,IP6.DNS dev show 2>&1 || true
            echo
            echo "== probes =="
            getent hosts example.com 2>&1 || true
            getent hosts one.one.one.one 2>&1 || true
            curl -fsS -o /dev/null -w "curl 1.1.1.1/cdn-cgi/trace HTTP %{http_code}\n" \
              --connect-timeout 5 --max-time 10 https://1.1.1.1/cdn-cgi/trace 2>&1 || true
          }

          cmd_restart_resolved() {
            need_root restart-resolved
            systemctl restart systemd-resolved
            resolvectl flush-caches 2>/dev/null || true
            resolvectl reset-server-features 2>/dev/null || true
            systemctl --no-pager --full status systemd-resolved | head -n 40 || true
          }

          cmd_plain() {
            need_root plain
            default_public_resolv
          }

          cmd_dhcp() {
            need_root dhcp
            mapfile -t dns_list < <(
              nmcli -g IP4.DNS dev show 2>/dev/null \
                | tr '|' '\n' \
                | sed 's/\\//g' \
                | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' \
                | awk '!seen[$0]++'
            )
            if [ "''${#dns_list[@]}" -eq 0 ]; then
              echo "no NM IPv4 DNS found; using plain public resolvers" >&2
              default_public_resolv
              return
            fi
            lines=("# dns-emergency dhcp — from NetworkManager link DNS")
            for ns in "''${dns_list[@]}"; do
              lines+=("nameserver $ns")
            done
            lines+=("options edns0")
            write_resolv_lines "''${lines[@]}"
          }

          cmd_disable_dot() {
            need_root disable-dot
            mkdir -p /run/systemd/resolved.conf.d
            printf '%s\n' \
              "# Temporary: dns-emergency disable-dot (reboot clears /run)" \
              "[Resolve]" \
              "DNSOverTLS=no" \
              >/run/systemd/resolved.conf.d/99-dns-emergency-no-dot.conf
            systemctl restart systemd-resolved
            resolvectl flush-caches 2>/dev/null || true
            echo "DNSOverTLS disabled via /run/systemd/resolved.conf.d/99-dns-emergency-no-dot.conf"
            echo "Undo: sudo rm -f /run/systemd/resolved.conf.d/99-dns-emergency-no-dot.conf && sudo systemctl restart systemd-resolved"
          }

          cmd_restore() {
            need_root restore
            rm -f /run/systemd/resolved.conf.d/99-dns-emergency-no-dot.conf 2>/dev/null || true
            default_public_resolv
            systemctl start systemd-resolved 2>/dev/null || true
            resolvectl flush-caches 2>/dev/null || true
            echo "restored flake-default public /etc/resolv.conf and started systemd-resolved"
          }

          # NSS is `resolve [!UNAVAIL=return] … dns`. If resolved is *running* but
          # broken, queries do not fall through. Stopping it makes the module UNAVAIL
          # so glibc uses /etc/resolv.conf public DNS immediately.
          # Source: man nsswitch.conf; man systemd-resolved.service
          cmd_stop_resolved() {
            need_root stop-resolved
            default_public_resolv
            systemctl stop systemd-resolved 2>/dev/null || true
            echo "systemd-resolved stopped; NSS should use /etc/resolv.conf public DNS"
            echo "Bring back: sudo dns-emergency restore"
          }

          cmd_flush() {
            need_root flush
            resolvectl flush-caches
            resolvectl reset-server-features
            resolvectl statistics 2>&1 | head -n 40 || true
          }

          cmd_test() {
            host="''${1:-example.com}"
            echo "getent hosts $host"
            getent hosts "$host" || true
            echo
            echo "curl -I https://$host"
            curl -fsSI --connect-timeout 5 --max-time 15 "https://$host" 2>&1 | head -n 15 || true
            echo
            echo "curl https://1.1.1.1/cdn-cgi/trace (IP literal)"
            curl -fsS --connect-timeout 5 --max-time 10 https://1.1.1.1/cdn-cgi/trace 2>&1 || true
          }

          cmd="''${1:-}"
          case "$cmd" in
            ""|-h|--help|help) usage ;;
            status) cmd_status ;;
            restart-resolved) cmd_restart_resolved ;;
            plain) cmd_plain ;;
            dhcp) cmd_dhcp ;;
            disable-dot) cmd_disable_dot ;;
            restore) cmd_restore ;;
            stop-resolved) cmd_stop_resolved ;;
            flush) cmd_flush ;;
            test) shift || true; cmd_test "''${1:-}" ;;
            *)
              echo "unknown command: $cmd" >&2
              usage >&2
              exit 2
              ;;
          esac
        '';
      };

    in
    {
      config = lib.mkIf cfg.enable {
        networking = {
          hostName = config.environment.variables.HOST;

          # Prefer Cloudflare; #name is DoT SNI when DNSOverTLS is on.
          # DHCP/VPN link DNS still flows NM → resolved (captive portals).
          # Source: man resolved.conf (DNS=, DNSOverTLS=)
          nameservers = [
            "1.1.1.1#cloudflare-dns.com"
            "1.0.0.1#cloudflare-dns.com"
            "9.9.9.9#dns.quad9.net"
          ];

          networkmanager = {
            enable = true;
            # Feed link DNS into resolved (hotel captive portals need DHCP DNS).
            dns = "systemd-resolved";

            wifi = {
              # "random" breaks some networks; stable is enough privacy for most Wi-Fi.
              macAddress = "stable";
              scanRandMacAddress = true;
            };

            # Some VPS providers bind the public IP to the hardware MAC.
            ethernet.macAddress = "preserve";

            settings = {
              # Avoid broadcasting hostname on typical LANs; main_vps still needs
              # DHCP hostname for its provider lease.
              # Source: https://networkmanager.dev/docs/api/latest/NetworkManager.conf.html
              ipv4.dhcp-send-hostname = config.preferences.hostName != "main_vps";
              ipv6.dhcp-send-hostname = config.preferences.hostName != "main_vps";
            };

            plugins = with pkgs; [
              networkmanager-openvpn
              networkmanager-ssh
            ];
          };

          firewall.enable = true;

          # Prefer IPv4 when ISP/hotel IPv6 is broken so dual-stack apps do not stall.
          # Source: https://man7.org/linux/man-pages/man5/gai.conf.5.html
          getaddrinfo.precedence = {
            ":ffff:0:0/96" = 100;
            "::/0" = 40;
          };

          # Default NixOS NTP pool plus Cloudflare time anycast.
          # Source: https://developers.cloudflare.com/time-services/ntp/usage/
          timeServers = options.networking.timeServers.default ++ [
            "162.159.200.1"
            "162.159.200.123"
          ];
        };

        # Prefer DoT to Cloudflare; fall back to plain UDP/TCP DNS and link DNS.
        # DNSSEC off: captive portals and many hotel middleboxes break with DNSSEC.
        # Source: man systemd-resolved.service, man resolved.conf
        services.resolved = {
          enable = true;
          settings.Resolve = {
            DNSOverTLS = "opportunistic";
            DNSSEC = "no";
            LLMNR = "no";
            MulticastDNS = "no";
            ResolveUnicastSingleLabel = "no";
            # Only used when configured + link DNS are all unknown/unreachable.
            FallbackDNS = [
              "1.1.1.1"
              "1.0.0.1"
              "9.9.9.9"
              "8.8.8.8"
            ];
          };
        };

        # Static public nameservers in /etc/resolv.conf (NOT the 127.0.0.53 stub).
        # NSS order is `resolve [!UNAVAIL=return] … dns`: when resolved is up it still
        # prefers DoT + DHCP/VPN link DNS (captive portals); when resolved is dead or
        # UNAVAIL, glibc falls through to these public resolvers and internet keeps
        # working. Stub mode would hard-fail every classic client if resolved dies.
        # Captive portal stuck on public DNS? `sudo dns-emergency dhcp`.
        # Source: man systemd-resolved.service; man nsswitch.conf
        environment.etc."resolv.conf".text = lib.mkForce ''
          # Managed by modules/common/networking.nix — public DNS fail-open.
          # Prefer resolved (DoT/link DNS) via NSS when available; these are fallback.
          nameserver 1.1.1.1
          nameserver 1.0.0.1
          nameserver 9.9.9.9
          nameserver 8.8.8.8
          options edns0
        '';

        # resolved is on the critical path for nss-resolve and NM DNS push; never sit
        # in failed/start-limit after a transient OpenSnitch/boot race.
        # Source: systemd.service(5) Restart=, StartLimitIntervalSec=
        systemd.services.systemd-resolved = {
          startLimitIntervalSec = 0;
          serviceConfig = {
            Restart = "always";
            RestartSec = "2s";
          };
        };

        services.opensnitch.mutableRules = lib.mkIf config.services.opensnitch.enable {
          "010-allow-networkmanager-lan" =
            opensnitchRule "010-allow-networkmanager-lan"
              "Allow NetworkManager LAN access for DHCP/captive-portal/link management."
              (list [
                (simple "process.path" "${pkgs.networkmanager}/bin/NetworkManager")
                (network "dest.network" "LAN")
              ]);
          "010-allow-systemd-resolved-dns" =
            opensnitchRule "010-allow-systemd-resolved-dns"
              "Allow systemd-resolved plain DNS (53) and DoT (853); FallbackDNS keeps internet up if DoT fails."
              (list [
                (simple "process.path" "${pkgs.systemd}/lib/systemd/systemd-resolved")
                (regexp "dest.port" "^(53|853)$")
              ]);
          "010-allow-systemd-timesyncd-ntp" =
            opensnitchRule "010-allow-systemd-timesyncd-ntp" "Allow systemd-timesyncd NTP on port 123."
              (list [
                (simple "process.path" "${pkgs.systemd}/lib/systemd/systemd-timesyncd")
                (simple "dest.port" "123")
              ]);
        };

        # OpenVPN often pushes IPv6 full-tunnel routes without a GUA on tun, which
        # blackholes dual-stack clients. Drop those routes only — never touch DNS.
        # Source: https://community.openvpn.net/openvpn/ticket/1163
        networking.networkmanager.dispatcherScripts = [
          {
            source = pkgs.writeShellScript "vpn-drop-broken-ipv6" ''
              INTERFACE="$1"
              ACTION="$2"

              case "$ACTION" in
                up|vpn-up|reapply|dhcp4-change|dhcp6-change) ;;
                *) exit 0 ;;
              esac

              case "$INTERFACE" in
                tun*|tap*|wg*|proton*|nordlynx*) ;;
                *) exit 0 ;;
              esac

              ${pkgs.iproute2}/bin/ip -6 route del 2000::/3 dev "$INTERFACE" 2>/dev/null || true
              ${pkgs.iproute2}/bin/ip -6 route del ::/1 dev "$INTERFACE" 2>/dev/null || true
              ${pkgs.iproute2}/bin/ip -6 route del 8000::/1 dev "$INTERFACE" 2>/dev/null || true
              ${pkgs.iproute2}/bin/ip -6 route del default dev "$INTERFACE" 2>/dev/null || true

              if ! ${pkgs.iproute2}/bin/ip -6 -o addr show dev "$INTERFACE" scope global 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q .; then
                ${pkgs.procps}/bin/sysctl -w "net.ipv6.conf.$INTERFACE.disable_ipv6=1" >/dev/null 2>&1 || true
              fi
            '';
            type = "basic";
          }
        ];

        environment.variables.VPN_DIR = config.preferences.paths.vpnDirectory;

        environment.systemPackages = [
          pkgs.openvpn
          dnsEmergency
        ];
      };
    };
}
