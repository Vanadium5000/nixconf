{
  self,
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

      # Write OVPN config to a user-accessible location for nmcli import
      # Uses mode 0644 so the user can read it for import
      ovpnConfig = pkgs.writeTextFile {
        name = "airvpn.ovpn";
        text = self.secrets.AIRVPN_OVPN or "";
        destination = "/airvpn.ovpn";
      };
    in
    {
      config = lib.mkIf cfg.enable {
        networking = {
          hostName = config.environment.variables.HOST;

          # CLI/TUI for connecting to networks
          networkmanager = {
            enable = true;

            # Prevents networkmanager override set nameservers
            dns = "systemd-resolved";

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

          # Use custom DNS
          nameservers = [
            "1.1.1.1#cloudflare-dns.com" # Cloudflare
            "1.0.0.1#cloudflare-dns.com" # Cloudflare
            "9.9.9.10#dns10.quad9.net" # Quad9 + no "threat" blocking
          ];

          # NTP servers - https://wiki.nixos.org/wiki/NTP
          timeServers =
            options.networking.timeServers.default
            # https://developers.cloudflare.com/time-services/ntp/usage/
            ++ [
              "162.159.200.1"
              "162.159.200.123"
            ];
        };

        # DNS encryption over TLS
        # Troubleshooting Tool:
        #  resolvectl status
        #  resolvectl query <hostname>
        services.resolved = {
          enable = true;

          dnssec = "allow-downgrade"; # "true" | "allow-downgrade" | "false"
          dnsovertls = "opportunistic"; # "true" | "opportunistic" | "false"
          domains = [ "~." ]; # "use as default interface for all requests"

          # (see man resolved.conf)
          # let Avahi handle mDNS publication
          # extraConfig = ''
          #   MulticastDNS=resolve
          # '';

          # llmnr = "true"; # full LLMNR responder and resolver support
        };

        # VPN: Make OVPN config available for import
        # Stored in nix store (world-readable) - credentials are encrypted within the ovpn file
        environment.variables.AIRVPN_OVPN_PATH = "${ovpnConfig}/airvpn.ovpn";

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
