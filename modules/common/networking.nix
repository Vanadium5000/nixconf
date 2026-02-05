# Networking module with encrypted DNS via dnscrypt-proxy
# ALL DNS is routed through dnscrypt-proxy (127.0.0.1) - DHCP/VPN DNS is ignored
{
  ...
}:
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
    in
    {
      config = lib.mkIf cfg.enable {
        networking = {
          hostName = config.environment.variables.HOST;

          # Primary DNS is dnscrypt-proxy on localhost:54 (port 53 reserved for external service)
          nameservers = [
            "127.0.0.1:54"
            "[::1]:54" # IPv6 loopback with explicit port
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

            # Also randomize ethernet
            ethernet.macAddress = "random";

            # Global defaults for all new + existing connections for better privacy
            settings = {
              # Very important: prevents sending your real hostname to every network
              connection.dhcp-send-hostname = false;
            };

            plugins = with pkgs; [
              networkmanager-openvpn # This provides the org.freedesktop.NetworkManager.openvpn plugin
              networkmanager-ssh # SSH VPN integration for NetworkManager
            ];
          };

          # Better security
          firewall.enable = true;

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

          # Fallback to common public DNS if dnscrypt-proxy is down (e.g. captive portals)
          # These are ONLY used when primary DNS (127.0.0.1) fails
          fallbackDns = [
            "1.1.1.1"
            "9.9.9.9"
          ];

          # Route ALL queries through the global DNS servers (127.0.0.1 → dnscrypt-proxy)
          # The "~." is a routing-only domain that captures all queries
          domains = [ "~." ];

          # Disable LLMNR and mDNS to prevent local network DNS leaks
          llmnr = "false";

          # DNSSEC breaks captive portals and some misconfigured domains
          dnssec = "false";

          extraConfig = ''
            MulticastDNS=no
            # Disable stub listener on port 53 - reserved for external service
            DNSStubListener=no
            DNSStubListenerExtra=
            ResolveUnicastSingleLabel=no
          '';
        };

        # Use non-stub resolv.conf since stub listener is disabled (port 53 reserved)
        # This file contains the actual upstream DNS (127.0.0.1:54 → dnscrypt-proxy)
        environment.etc."resolv.conf".source = lib.mkForce "/run/systemd/resolve/resolv.conf";

        # ============================================================================
        # Encrypted DNS via dnscrypt-proxy
        # ============================================================================
        services.dnscrypt-proxy = {
          enable = true;

          settings = {
            # Listen on localhost for both IPv4 and IPv6
            # 53 changed to 54 to avoid conflicts with dnsmasq
            listen_addresses = [
              "127.0.0.1:54"
              "[::1]:54" # IPv6 loopback listener
            ];

            # Server selection criteria - privacy focused, no DNSSEC requirement
            # (DNSSEC breaks captive portals and some sites)
            require_dnssec = false;
            require_nolog = true;
            require_nofilter = true;

            # Protocol support
            ipv4_servers = true;
            ipv6_servers = true;
            doh_servers = true; # DNS-over-HTTPS (most firewall-friendly)
            dnscrypt_servers = true; # DNSCrypt protocol

            # Prefer specific trusted servers (checked first before auto-selection)
            # If these fail, falls back to auto-selected servers from the public list
            server_names = [
              "cloudflare"
              "cloudflare-ipv6" # Explicit IPv6 variant for Cloudflare
              "quad9-dnscrypt-ip4-nofilter-pri"
              "quad9-dnscrypt-ip6-nofilter-pri"
              "quad9-doh-ip4-nofilter-pri"
              "quad9-doh-ip6-nofilter-pri"
            ];

            cache = true;
            cache_size = 4096; # Number of cached entries
            cache_min_ttl = 2400; # 40 minutes minimum
            cache_max_ttl = 86400; # 24 hours maximum
            cache_neg_min_ttl = 60; # Cache negative responses (NXDOMAIN) for 1 min
            cache_neg_max_ttl = 600; # Max 10 minutes for negative cache

            # Public server list - auto-updated and verified
            sources.public-resolvers = {
              urls = [
                "https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/public-resolvers.md"
                "https://download.dnscrypt.info/resolvers-list/v3/public-resolvers.md"
              ];
              cache_file = "/var/lib/dnscrypt-proxy/public-resolvers.md";
              minisign_key = "RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3";
              refresh_delay = 72; # Hours between updates
            };

            # Bootstrap resolvers - used ONLY for initial server list download
            # These are NOT used for regular queries after startup
            bootstrap_resolvers = [
              "1.1.1.1:53"
              "9.9.9.9:53"
            ];
            ignore_system_dns = true;

            # Connection settings - fail fast to trigger fallback
            timeout = 3000; # 3s timeout (down from 5s)
            keepalive = 30; # Keepalive for HTTP/2 connections in seconds
          };
        };

        # Ensure dnscrypt-proxy can write its state (server lists, cache)
        systemd.services.dnscrypt-proxy.serviceConfig = {
          StateDirectory = "dnscrypt-proxy";
        };

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

              # Only act on connection up events
              case "$ACTION" in
                up|vpn-up)
                  ;;
                *)
                  exit 0
                  ;;
              esac

              # Skip if no connection UUID
              [ -z "$CONNECTION_UUID" ] && exit 0

              # Skip tailscale (manages its own DNS correctly with routing domains)
              case "$INTERFACE" in
                tailscale*)
                  exit 0
                  ;;
              esac

              # Check if ignore-auto-dns is already set
              IPV4_IGNORE=$(${pkgs.networkmanager}/bin/nmcli -g ipv4.ignore-auto-dns connection show "$CONNECTION_UUID" 2>/dev/null)
              IPV6_IGNORE=$(${pkgs.networkmanager}/bin/nmcli -g ipv6.ignore-auto-dns connection show "$CONNECTION_UUID" 2>/dev/null)

              # Set ignore-auto-dns if not already set
              if [ "$IPV4_IGNORE" != "yes" ] || [ "$IPV6_IGNORE" != "yes" ]; then
                ${pkgs.networkmanager}/bin/nmcli connection modify "$CONNECTION_UUID" \
                  ipv4.ignore-auto-dns yes \
                  ipv6.ignore-auto-dns yes 2>/dev/null || true

                # Reactivate to apply (only for non-VPN, VPNs auto-apply)
                if [ "$ACTION" = "up" ]; then
                  ${pkgs.networkmanager}/bin/nmcli connection up "$CONNECTION_UUID" 2>/dev/null &
                fi
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

        environment.variables.VPN_DIR = "/home/${config.preferences.user.username}/Shared/VPNs";

        environment.systemPackages = with pkgs; [
          dnscrypt-proxy
        ];
      };
    };
}
