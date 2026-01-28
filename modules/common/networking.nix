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

          # Primary DNS is dnscrypt-proxy on localhost
          nameservers = [
            "127.0.0.1"
            "::1"
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
            # Fail faster when upstream is unresponsive (default is 5s per server)
            DNSStubListenerExtra=
            ResolveUnicastSingleLabel=no
          '';
        };

        # Ensure /etc/resolv.conf points to systemd-resolved stub
        environment.etc."resolv.conf".source = "/run/systemd/resolve/stub-resolv.conf";

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
        # Force ALL interfaces to use global DNS (not DHCP/VPN-pushed DNS)
        # ============================================================================
        # NetworkManager's dns=none only affects /etc/resolv.conf management.
        # The internal DHCP client STILL pushes per-link DNS to systemd-resolved
        # via DBus. This dispatcher clears that immediately after any interface
        # comes up, ensuring all DNS goes through global (127.0.0.1 → dnscrypt-proxy).
        networking.networkmanager.dispatcherScripts = [
          {
            source = pkgs.writeShellScript "force-global-dns" ''
              INTERFACE="$1"
              ACTION="$2"

              # Act on any event that might set DNS
              case "$ACTION" in
                up|vpn-up|dhcp4-change|dhcp6-change|connectivity-change)
                  ;;
                *)
                  exit 0
                  ;;
              esac

              # Skip loopback and tailscale (tailscale manages its own DNS correctly)
              case "$INTERFACE" in
                lo|tailscale*)
                  exit 0
                  ;;
              esac

              # Force interface to NOT be default route for DNS
              # This ensures global DNS (127.0.0.1 → dnscrypt-proxy) always wins
              ${pkgs.systemd}/bin/resolvectl default-route "$INTERFACE" false 2>/dev/null || true

              # Clear any per-link DNS servers pushed by DHCP
              ${pkgs.systemd}/bin/resolvectl dns "$INTERFACE" "" 2>/dev/null || true

              # Clear any per-link search/routing domains
              ${pkgs.systemd}/bin/resolvectl domain "$INTERFACE" "" 2>/dev/null || true
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
