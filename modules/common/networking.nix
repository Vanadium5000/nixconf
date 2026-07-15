# Networking module with encrypted DNS via dnscrypt-proxy
# ALL DNS is routed through dnscrypt-proxy (127.0.0.1) - DHCP/VPN DNS is ignored
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
    in
    {
      config = lib.mkIf cfg.enable {
        networking = {
          hostName = config.environment.variables.HOST;

          # Global DNS for systemd-resolved only (not classic /etc/resolv.conf).
          # Classic clients use the stub listener at 127.0.0.53:53 → resolved → :54.
          # Source: man systemd-resolved.service, resolv.conf modes (stub vs uplink).
          nameservers = [
            "127.0.0.1:54"
            "[::1]:54"
          ];

          # CLI/TUI for connecting to networks
          networkmanager = {
            enable = true;

            # Prevent NetworkManager from pushing per-link DNS to systemd-resolved
            # This ensures ALL DNS goes through global (127.0.0.1 → dnscrypt-proxy)
            dns = lib.mkForce "none";

            wifi = {
              macAddress = "stable"; # Randomize MAC for Wi-Fi connections - "random" breaks networks
              scanRandMacAddress = true; # Also randomize during Wi-Fi scans for extra privacy
            };

            # Preserve the hardware MAC on ethernet because some VPS providers bind IPs to it.
            ethernet.macAddress = "preserve";

            # Global defaults for all new + existing connections for better privacy
            settings = {
              # Prevents broadcasting the machine hostname on typical networks.
              # NetworkManager 1.52 rejects the old [connection] key; these are
              # the documented global defaults consumed by DHCP connection profiles.
              # The server host still needs DHCP hostname announcements for its provider lease.
              # Source: https://networkmanager.dev/docs/api/latest/NetworkManager.conf.html#connection-section
              ipv4.dhcp-send-hostname = config.preferences.hostName != "main_vps";
              ipv6.dhcp-send-hostname = config.preferences.hostName != "main_vps";
            };

            plugins = with pkgs; [
              networkmanager-openvpn # This provides the org.freedesktop.NetworkManager.openvpn plugin
              networkmanager-ssh # SSH VPN integration for NetworkManager
            ];
          };

          # Better security
          firewall.enable = true;

          # Prefer IPv4 when the ISP/hotel path has broken or blackholed IPv6.
          # Without this, dual-stack apps (Sober/Roblox, browsers, Electron) stall on
          # Happy Eyeballs waiting for unreachable AAAA targets.
          # Source: https://man7.org/linux/man-pages/man5/gai.conf.5.html
          getaddrinfo.precedence = {
            ":ffff:0:0/96" = 100; # IPv4-mapped / prefer IPv4
            "::/0" = 40;
          };

          # NTP servers - https://wiki.nixos.org/wiki/NTP
          timeServers =
            options.networking.timeServers.default
            # https://developers.cloudflare.com/time-services/ntp/usage/
            ++ [
              "162.159.200.1"
              "162.159.200.123"
            ];
        };

        # ============================================================================
        # systemd-resolved - Global DNS only (no per-link DNS)
        # ============================================================================
        services.resolved = {
          enable = true;

          settings.Resolve = {
            # Fallback only if dnscrypt-proxy is completely down. Prefer DoH/DoT-capable
            # public resolvers as last resort — never the hotel/ISP DHCP resolver.
            FallbackDNS = [
              "1.1.1.1"
              "9.9.9.9"
            ];

            # Route ALL queries through the global DNS servers (127.0.0.1:54 → dnscrypt-proxy).
            # The "~." routing-only domain captures all queries.
            Domains = [ "~." ];

            # Disable local multicast/name protocols to prevent local-network DNS leaks.
            LLMNR = "no";
            MulticastDNS = "no";

            # DNSSEC breaks captive portals and some misconfigured domains.
            DNSSEC = "no";

            # Stub UDP+TCP on 127.0.0.53:53. With DNSStubListener=no, resolved drops
            # nameserver 127.0.0.1:54 from uplink resolv.conf (glibc has no :port form),
            # so classic clients (host/curl/nix sandboxes) get an empty resolv and fail
            # with "Could not resolve host". Stub mode always writes nameserver 127.0.0.53.
            # Source: man systemd-resolved.service; live host github.com → connection refused on :53.
            DNSStubListener = "yes";
            ResolveUnicastSingleLabel = "no";
          };
        };

        # Force stub resolv.conf. Without this, NixOS may still point at uplink resolv
        # (empty when only :54 globals exist). Always list 127.0.0.53 for classic DNS.
        # Source: https://wiki.archlinux.org/title/Systemd-resolved#DNS
        environment.etc."resolv.conf".source = lib.mkForce "/run/systemd/resolve/stub-resolv.conf";

        # ============================================================================
        # Encrypted DNS via dnscrypt-proxy
        # ============================================================================
        services.dnscrypt-proxy = {
          enable = true;
          # Do not merge package example defaults (they re-enable IPv6 resolvers and
          # UDP-first probe settings that break hotel/VPN paths). Own the full TOML.
          # Source: nixpkgs services.dnscrypt-proxy.upstreamDefaults merge via jq add.
          upstreamDefaults = false;

          settings = {
            # Listen on localhost:54 (resolved stub owns :53 for app-facing DNS).
            listen_addresses = [
              "127.0.0.1:54"
              "[::1]:54"
            ];

            # Server selection criteria - privacy focused, no DNSSEC requirement
            # (DNSSEC breaks captive portals and some sites)
            require_dnssec = false;
            require_nolog = true;
            require_nofilter = true;

            # Broken hotel/ISP IPv6 makes dnscrypt pick cloudflare-ipv6 then TIMEOUT;
            # stick to IPv4 + DoH so DNS does not depend on working native IPv6.
            # Source: live logs "Server with lowest latency: cloudflare-ipv6" + v6 unreachable.
            ipv4_servers = true;
            ipv6_servers = false;
            doh_servers = true; # DNS-over-HTTPS (most firewall-friendly / hard to break)
            # DNSCrypt stamps time out on this hotel/VPN path; DoH on :443 is enough.
            # Source: live logs repeatedly "quad9-dnscrypt-ip4-nofilter-pri TIMEOUT".
            dnscrypt_servers = false;
            # TCP/DoH path survives flaky UDP filtering better than raw DNSCrypt UDP.
            force_tcp = true;

            # Prefer IPv4 DoH stamps that survive OpenSnitch/hotel TLS inspection better
            # than raw DNSCrypt UDP. Names must match static.* entries below when the
            # public-resolvers list has not been downloaded yet (impermanent root).
            server_names = [
              "cloudflare"
              "quad9-doh-ip4-port443-nofilter-pri"
              "google"
            ];

            cache = true;
            cache_size = 4096;
            cache_min_ttl = 60; # Avoid hammering upstream on flaky links
            cache_max_ttl = 86400;
            cache_neg_min_ttl = 10; # Short negative cache so transient failures recover fast
            cache_neg_max_ttl = 60;

            sources.public-resolvers = {
              urls = [
                "https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/public-resolvers.md"
                "https://download.dnscrypt.info/resolvers-list/v3/public-resolvers.md"
              ];
              cache_file = "/var/lib/dnscrypt-proxy/public-resolvers.md";
              minisign_key = "RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3";
              refresh_delay = 72;
            };

            # Static stamps keep DNS up even when the public-resolvers download fails
            # (TLS handshake failures at boot / start-limit-hit). Stamps taken from the
            # live public-resolvers.md corpus on 2026-07-15.
            # Source: https://github.com/DNSCrypt/dnscrypt-proxy/wiki/Configuration#static-servers
            static = {
              cloudflare.stamp = "sdns://AgcAAAAAAAAABzEuMC4wLjEAEmRucy5jbG91ZGZsYXJlLmNvbQovZG5zLXF1ZXJ5";
              google.stamp = "sdns://AgUAAAAAAAAABzguOC44LjggsKKKE4EwvtIbNjGjagI2607EdKSVHowYZtyvD9iPrkkHOC44LjguOAovZG5zLXF1ZXJ5";
              "quad9-doh-ip4-port443-nofilter-pri".stamp =
                "sdns://AgcAAAAAAAAACDkuOS45LjEwILAZIHRLu3bJqwU-AeB7fgUORz0g95976kNfr-Q8nSQvE2RuczEwLnF1YWQ5Lm5ldDo0NDMKL2Rucy1xdWVyeQ";
            };

            # Bootstrap only for downloading the resolver list — IPv4 literals, no system DNS.
            bootstrap_resolvers = [
              "1.1.1.1:53"
              "9.9.9.9:53"
              "8.8.8.8:53"
            ];
            ignore_system_dns = true;
            # Probe HTTPS, not classic DNS: port 53 is often filtered and would stall
            # netprobe for netprobe_timeout while DNS stays unusable.
            netprobe_address = "1.1.1.1:443";
            netprobe_timeout = 10;
            block_ipv6 = true; # Apps get A-only answers → no Happy-Eyeballs stall on dead v6

            # OpenSnitch review pauses can exceed dnscrypt-proxy's default
            # 5s socket timeout; 25s keeps bootstrap/DoH attempts reviewable.
            # Source: https://github.com/DNSCrypt/dnscrypt-proxy/wiki/Configuration
            timeout = 25000;
            keepalive = 30;
          };
        };

        services.opensnitch.mutableRules = lib.mkIf config.services.opensnitch.enable {
          "010-allow-dnscrypt-proxy-service-ports" =
            opensnitchRule "010-allow-dnscrypt-proxy-service-ports"
              "Allow dnscrypt-proxy bootstrap, DNSCrypt, DoH, and DoT service ports; regular clients must still use localhost."
              (list [
                (simple "process.path" "${pkgs.dnscrypt-proxy}/bin/dnscrypt-proxy")
                (regexp "dest.port" "^(53|443|853)$")
              ]);
          "010-allow-networkmanager-lan" =
            opensnitchRule "010-allow-networkmanager-lan"
              "Allow NetworkManager to reach LAN services for DHCP/captive-portal/link management without allowing arbitrary internet destinations."
              (list [
                (simple "process.path" "${pkgs.networkmanager}/bin/NetworkManager")
                (network "dest.network" "LAN")
              ]);
          "010-allow-systemd-resolved-dns" =
            opensnitchRule "010-allow-systemd-resolved-dns"
              "Allow systemd-resolved only for classic DNS port 53; normal configured traffic stays loopback to dnscrypt-proxy."
              (list [
                (simple "process.path" "${pkgs.systemd}/lib/systemd/systemd-resolved")
                (simple "dest.port" "53")
              ]);
          "010-allow-systemd-timesyncd-ntp" =
            opensnitchRule "010-allow-systemd-timesyncd-ntp"
              "Allow systemd-timesyncd NTP only on port 123 instead of host-specific pool rules."
              (list [
                (simple "process.path" "${pkgs.systemd}/lib/systemd/systemd-timesyncd")
                (simple "dest.port" "123")
              ]);
        };

        # dnscrypt-proxy must survive early-boot TLS/OpenSnitch races: default
        # RestartSec=100ms + StartLimitBurst=5/10s hit start-limit and stayed dead
        # until a manual start (live journal: FATAL tls handshake → start-limit-hit).
        # Static stamps above mean a restart can serve DNS without re-fetching the list.
        # Source: systemd.unit(5) StartLimitIntervalSec=0; live legion5i journal 20:29.
        systemd.services.dnscrypt-proxy = {
          after = [
            "network-online.target"
            "nss-lookup.target"
            "opensnitchd.service"
          ];
          wants = [
            "network-online.target"
            "nss-lookup.target"
          ];
          # Unlimited restarts; backoff is RestartSec, not a hard fail.
          startLimitIntervalSec = 0;
          serviceConfig = {
            StateDirectory = "dnscrypt-proxy";
            Restart = "always";
            RestartSec = "5s";
          };
        };

        # Persist DynamicUser state so public-resolvers.md survives impermanent root.
        # Without this every boot re-downloads the list and can FATAL before start-limit.
        # Source: systemd DynamicUser StateDirectory → /var/lib/private/<name>
        impermanence.nixos.directories = [
          "/var/lib/private/dnscrypt-proxy"
        ];

        # ============================================================================
        # Force ALL connections to ignore DHCP-provided DNS
        # ============================================================================
        # NetworkManager's dns=none only affects /etc/resolv.conf management.
        # The internal DHCP client STILL pushes per-link DNS to systemd-resolved
        # via DBus. The ONLY reliable fix is setting ignore-auto-dns on each
        # connection profile. This dispatcher does that on first activation.
        networking.networkmanager.dispatcherScripts = [
          {
            source = pkgs.writeShellScript "force-ignore-auto-dns" ''
              INTERFACE="$1"
              ACTION="$2"
              CONNECTION_UUID="$3"

              case "$ACTION" in
                up|vpn-up|reapply|dhcp4-change|dhcp6-change)
                  ;;
                *)
                  exit 0
                  ;;
              esac

              [ -z "$CONNECTION_UUID" ] && exit 0

              # Skip tailscale (manages its own DNS correctly with routing domains)
              case "$INTERFACE" in
                tailscale*)
                  exit 0
                  ;;
              esac

              # Always force: no DHCP/VPN-pushed DNS, empty static DNS lists, IPv6 off.
              # Hotel/ISP (10.0.0.1) and PIA/AirVPN dhcp-option DNS must never become
              # per-link resolvers; global path is always resolved → dnscrypt :54.
              ${pkgs.networkmanager}/bin/nmcli connection modify "$CONNECTION_UUID" \
                ipv4.ignore-auto-dns yes \
                ipv6.ignore-auto-dns yes \
                ipv4.dns "" \
                ipv6.dns "" \
                ipv6.method disabled \
                ipv4.dns-priority 100 \
                2>/dev/null || true

              # Drop any resolved per-link DNS that snuck in before modify.
              ${pkgs.systemd}/bin/resolvectl dns "$INTERFACE" "" 2>/dev/null || true
              ${pkgs.systemd}/bin/resolvectl domain "$INTERFACE" "" 2>/dev/null || true
              # Keep "~." only on the global config so VPN links cannot capture DNS.
              ${pkgs.systemd}/bin/resolvectl default-route "$INTERFACE" no 2>/dev/null || true
            '';
            type = "basic";
          }
          {
            # OpenVPN/PIA often push redirect-gateway ipv6 / route-ipv6 without assigning a GUA
            # on tun. That installs 2000::/3 via tun with only fe80::, so dual-stack clients fail
            # Happy Eyeballs and can land on local nginx magic-DNS (ACP UI). Strip those routes
            # and refuse IPv6 on VPN tunnels unless a global address exists.
            # Source: https://community.openvpn.net/openvpn/ticket/1163
            source = pkgs.writeShellScript "vpn-drop-broken-ipv6" ''
              INTERFACE="$1"
              ACTION="$2"

              case "$ACTION" in
                up|vpn-up|reapply|dhcp4-change|dhcp6-change)
                  ;;
                *)
                  exit 0
                  ;;
              esac

              case "$INTERFACE" in
                tun*|tap*|wg*|proton*|nordlynx*)
                  ;;
                *)
                  exit 0
                  ;;
              esac

              # Always drop the common IPv6 full-tunnel blackhole prefix.
              ${pkgs.iproute2}/bin/ip -6 route del 2000::/3 dev "$INTERFACE" 2>/dev/null || true
              ${pkgs.iproute2}/bin/ip -6 route del ::/1 dev "$INTERFACE" 2>/dev/null || true
              ${pkgs.iproute2}/bin/ip -6 route del 8000::/1 dev "$INTERFACE" 2>/dev/null || true
              ${pkgs.iproute2}/bin/ip -6 route del default dev "$INTERFACE" 2>/dev/null || true

              # If the tunnel has no global IPv6 address, disable IPv6 on it entirely.
              if ! ${pkgs.iproute2}/bin/ip -6 -o addr show dev "$INTERFACE" scope global 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q .; then
                ${pkgs.procps}/bin/sysctl -w "net.ipv6.conf.$INTERFACE.disable_ipv6=1" >/dev/null 2>&1 || true
              fi
            '';
            type = "basic";
          }
        ];

        # ============================================================================
        # Manual DNS testing
        # ============================================================================
        #
        # Check active resolvers + fallback state:
        #   resolvectl status
        #
        # Query via dnscrypt-proxy explicitly (IPv4):
        #   resolvectl query example.com @127.0.0.1
        #
        # Query via dnscrypt-proxy explicitly (IPv6):
        #   resolvectl query example.com @::1
        #
        # Direct dnscrypt-proxy internal test:
        #   dnscrypt-proxy -resolve example.com
        #

        environment.variables.VPN_DIR = config.preferences.paths.vpnDirectory;

        environment.systemPackages = with pkgs; [
          dnscrypt-proxy
          openvpn
        ];
      };
    };
}
