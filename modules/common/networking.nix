# Networking module with encrypted DNS via dnscrypt-proxy2
#
# Why dnscrypt-proxy2 over systemd-resolved?
# - More reliable: no service restart issues after network changes
# - Better encryption: supports DNSCrypt protocol + DNS-over-HTTPS (DoH)
# - Memory-safe: written in Go vs C
# - Auto server selection: picks fastest responding servers
# - Built-in caching and DNSSEC validation
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

          # Point all DNS queries to local dnscrypt-proxy2 instance
          # IMPORTANT: Must be static to prevent DHCP/NetworkManager override
          nameservers = [
            "127.0.0.1"
            "::1"
          ];

          # CLI/TUI for connecting to networks
          networkmanager = {
            enable = true;

            # Disable NetworkManager's DNS handling - we use dnscrypt-proxy2
            # Options: "default" | "dnsmasq" | "systemd-resolved" | "none"
            dns = "none";

            wifi = {
              macAddress = "random"; # Randomize MAC for Wi-Fi connections
              scanRandMacAddress = true; # Also randomize during Wi-Fi scans for extra privacy
            };

            # Also randomize ethernet
            ethernet.macAddress = "random";

            # Global defaults for all new + existing connections for better privacy
            settings = {
              # Very important: prevents sending your real hostname to every network
              connection.dhcp-send-hostname = false;

              # Bonus: strong IPv6 privacy
              ipv6.ip6-privacy = 2;
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
        # Encrypted DNS via dnscrypt-proxy2
        # ============================================================================
        # Provides: DNSCrypt + DNS-over-HTTPS (DoH) + DNSSEC + caching
        #
        # Troubleshooting:
        #   systemctl status dnscrypt-proxy2     # Check service status
        #   journalctl -u dnscrypt-proxy2 -f     # Watch logs in real-time
        #   dig @127.0.0.1 example.com           # Test local DNS resolution
        #   cat /var/lib/dnscrypt-proxy2/*.md   # View downloaded server lists
        #
        # Common issues:
        #   - "connection refused": service not running, check journalctl
        #   - Slow first query: server list downloading, wait ~30s after boot
        #   - Captive portals broken: temporarily use `nmcli con mod <wifi> ipv4.dns "8.8.8.8"`
        #
        # Config reference: https://github.com/DNSCrypt/dnscrypt-proxy/blob/master/dnscrypt-proxy/example-dnscrypt-proxy.toml
        # ============================================================================
        services.dnscrypt-proxy2 = {
          enable = true;

          settings = {
            # Listen on localhost for both IPv4 and IPv6
            listen_addresses = [
              "127.0.0.1:53"
              "[::1]:53"
            ];

            # Server selection criteria - only use servers that meet ALL requirements
            require_dnssec = true; # DNSSEC validation mandatory
            require_nolog = true; # Servers must not log queries
            require_nofilter = true; # No content filtering (we decide what to block)

            # Protocol support
            ipv4_servers = true;
            ipv6_servers = false; # Enable if you have working IPv6
            doh_servers = true; # DNS-over-HTTPS (most firewall-friendly)
            dnscrypt_servers = true; # DNSCrypt protocol

            # Prefer specific trusted servers (checked first before auto-selection)
            # If these fail, falls back to auto-selected servers from the public list
            server_names = [
              "cloudflare"
              "cloudflare-ipv6"
              "quad9-dnscrypt-ip4-nofilter-pri"
              "quad9-doh-ip4-nofilter-pri"
            ];

            # Caching - reduces latency and external queries
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
              cache_file = "/var/lib/dnscrypt-proxy2/public-resolvers.md";
              minisign_key = "RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3";
              refresh_delay = 72; # Hours between updates
            };

            # Bootstrap resolvers - used ONLY for initial server list download
            # These are NOT used for regular queries after startup
            bootstrap_resolvers = [
              "1.1.1.1:53"
              "9.9.9.9:53"
            ];
            ignore_system_dns = true; # Don't fall back to system DNS

            # Connection settings
            timeout = 5000; # Query timeout in ms
            keepalive = 30; # Keepalive for HTTP/2 connections in seconds
          };
        };

        # Ensure dnscrypt-proxy2 can write its state (server lists, cache)
        systemd.services.dnscrypt-proxy2.serviceConfig = {
          StateDirectory = "dnscrypt-proxy2";
        };

        # VPN directory for .ovpn config files
        environment.variables.VPN_DIR = "/home/${config.preferences.user.username}/Shared/VPNs";

        # VPN packages
        environment.systemPackages = with pkgs; [
          openvpn
        ];

        # Local device discovery
        # services.avahi = {
        #   enable = true;
        #   nssmdns4 = true;
        #   openFirewall = true;
        # };

        # NTP and NTS client and server implementation
        # services.chrony.enable = true;
      };
    };
}
