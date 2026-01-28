{
  self,
  ...
}:
{
  flake.nixosModules.vpn-proxy-service =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    let
      inherit (lib) mkOption mkIf types;
      cfg = config.services.vpn-proxy;
    in
    {
      options.services.vpn-proxy = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Enable VPN SOCKS5 proxy service";
        };

        port = mkOption {
          type = types.port;
          default = 10800;
          description = "Port to listen on";
        };

        vpnDir = mkOption {
          type = types.str;
          default = "/home/${config.preferences.user.username}/Shared/VPNs";
          description = "Directory containing .ovpn files";
        };

        idleTimeout = mkOption {
          type = types.int;
          default = 300;
          description = "Seconds before idle VPN cleanup";
        };

        randomRotation = mkOption {
          type = types.int;
          default = 300;
          description = "Seconds between random VPN rotation";
        };
      };

      config = mkIf cfg.enable {
        systemd.services.vpn-proxy = {
          description = "VPN SOCKS5 Proxy Server";
          wantedBy = [ "multi-user.target" ];
          after = [ "network.target" ];

          path = [
            pkgs.bash
            pkgs.iproute2
            pkgs.iptables
            pkgs.nftables
            pkgs.openvpn
            pkgs.socat
            pkgs.coreutils
          ];

          environment = {
            VPN_DIR = cfg.vpnDir;
            VPN_PROXY_PORT = toString cfg.port;
            VPN_PROXY_IDLE_TIMEOUT = toString cfg.idleTimeout;
            VPN_PROXY_RANDOM_ROTATION = toString cfg.randomRotation;
          };

          serviceConfig = {
            Type = "simple";
            ExecStart = "${self.packages.${pkgs.system}.vpn-proxy}/bin/vpn-proxy serve";
            Restart = "on-failure";
            RestartSec = 5;

            # Hardening (runs as root for netns operations)
            NoNewPrivileges = false;
            ProtectSystem = "strict";
            ProtectHome = "read-only";
            ReadWritePaths = [ "/dev/shm" "/run/netns" "/var/run/netns" ];
            PrivateTmp = true;
          };
        };
      };
    };
}
