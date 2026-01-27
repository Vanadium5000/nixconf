# Networking module with encrypted DNS via dnscrypt-proxy
# Falls back to router/DHCP DNS ONLY if dnscrypt-proxy is down
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

          # Use systemd-resolved stub
          # Primary DNS is dnscrypt-proxy (127.0.0.1)
          # Fallback DNS comes from DHCP (router)
          nameservers = [
            "127.0.0.1"
            "::1" # IPv6 loopback support
          ];

          # CLI/TUI for connecting to networks
          networkmanager = {
            enable = true;

            # Let NetworkManager feed DHCP DNS to systemd-resolved
            dns = "systemd-resolved";

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
        # systemd-resolved (fallback-only)
        # ============================================================================
        services.resolved = {
          enable = true;

          # Router/DHCP DNS used ONLY if 127.0.0.1/::1 is unreachable
          # dnscrypt-proxy is the primary resolver
          fallbackDns = [ ];
        };

        # ============================================================================
        # Encrypted DNS via dnscrypt-proxy
        # ============================================================================
        services.dnscrypt-proxy = {
          enable = true;

          settings = {
            # Listen on localhost for both IPv4 and IPv6
            listen_addresses = [
              "127.0.0.1:53"
              "[::1]:53" # IPv6 loopback listener
            ];

            # Server selection criteria - only use servers that meet ALL requirements
            require_dnssec = true; # DNSSEC validation mandatory
            require_nolog = true; # Servers must not log queries
            require_nofilter = true; # No content filtering (we decide what to block)

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
            cache_min_ttl = 2400; # 40 minutes minimum cache
            cache_max_ttl = 86400; # 24 hours maximum cache
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

            # Connection settings
            timeout = 5000; # Query timeout in ms
            keepalive = 30; # Keepalive for HTTP/2 connections in seconds
          };
        };

        # Ensure dnscrypt-proxy can write its state (server lists, cache)
        systemd.services.dnscrypt-proxy.serviceConfig = {
          StateDirectory = "dnscrypt-proxy";
        };

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
        # Force router/DHCP DNS (bypass dnscrypt-proxy):
        #   resolvectl query example.com --legend=no
        #
        # Direct dnscrypt-proxy internal test:
        #   dnscrypt-proxy -resolve example.com
        #

        environment.variables.VPN_DIR = "/home/${config.preferences.user.username}/Shared/VPNs";
      };
    };
}
