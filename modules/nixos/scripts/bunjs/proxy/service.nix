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
      username = config.preferences.user.username;
    in
    {
      options.services.vpn-proxy = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Enable VPN proxy services (SOCKS5 and HTTP CONNECT)";
        };

        port = mkOption {
          type = types.port;
          default = 10800;
          description = "SOCKS5 proxy port";
        };

        httpPort = mkOption {
          type = types.port;
          default = 10801;
          description = "HTTP CONNECT proxy port";
        };

        vpnDir = mkOption {
          type = types.str;
          default = "/home/${username}/Shared/VPNs";
          description = "Directory containing .ovpn files";
        };

        idleTimeout = mkOption {
          type = types.int;
          default = 300;
          description = "Seconds before idle VPN namespace cleanup";
        };

        randomRotation = mkOption {
          type = types.int;
          default = 300;
          description = "Seconds between random VPN rotation";
        };
      };

      config = mkIf cfg.enable {
        # Ensure required directories exist before services start
        systemd.tmpfiles.rules = [
          "d /run/netns 0755 root root -"
          "d /etc/netns 0755 root root -"
        ];

        # Common environment variables for all proxy services
        systemd.services =
          let
            commonPath = [
              pkgs.bash
              pkgs.iproute2
              pkgs.iptables
              pkgs.nftables
              pkgs.openvpn
              pkgs.socat
              pkgs.coreutils
              pkgs.procps
              pkgs.jq
              pkgs.util-linux
              pkgs.gnugrep
              pkgs.gawk
              pkgs.findutils
              pkgs.microsocks
              # Notification tools for IPC-based notifications
              self.packages.${pkgs.stdenv.hostPlatform.system}.qs-notify
              self.packages.${pkgs.stdenv.hostPlatform.system}.qs-notifications
              pkgs.quickshell
            ];

            # UID 1000 is standard for first user; XDG_RUNTIME_DIR for Quickshell IPC
            commonEnv = {
              VPN_DIR = cfg.vpnDir;
              VPN_PROXY_PORT = toString cfg.port;
              VPN_HTTP_PROXY_PORT = toString cfg.httpPort;
              VPN_PROXY_IDLE_TIMEOUT = toString cfg.idleTimeout;
              VPN_PROXY_RANDOM_ROTATION = toString cfg.randomRotation;
              # Quickshell IPC requires XDG_RUNTIME_DIR to find the socket
              XDG_RUNTIME_DIR = "/run/user/1000";
              # HOME needed for qs-notifications to find QML file paths
              HOME = "/home/${username}";
            };

            commonServiceConfig = {
              NoNewPrivileges = false;
              ProtectSystem = "full";
              ProtectHome = "read-only";
              ReadWritePaths = [
                "/dev/shm"
                "/run/netns"
                "/var/run/netns"
                "/etc/netns"
                # Allow access to user's XDG_RUNTIME_DIR for Quickshell IPC
                "/run/user/1000"
              ];
              PrivateTmp = true;
            };
          in
          {
            # SOCKS5 Proxy Server
            vpn-proxy = {
              description = "VPN SOCKS5 Proxy Server";
              wantedBy = [ "multi-user.target" ];
              after = [ "network.target" ];

              path = commonPath;
              environment = commonEnv;

              serviceConfig = commonServiceConfig // {
                Type = "simple";
                ExecStart = "${self.packages.${pkgs.stdenv.hostPlatform.system}.vpn-proxy}/bin/vpn-proxy serve";
                Restart = "on-failure";
                RestartSec = 5;
              };
            };

            # HTTP CONNECT Proxy Server
            http-proxy = {
              description = "VPN HTTP CONNECT Proxy Server";
              wantedBy = [ "multi-user.target" ];
              after = [
                "network.target"
                "vpn-proxy.service"
              ];

              path = commonPath;
              environment = commonEnv;

              serviceConfig = commonServiceConfig // {
                Type = "simple";
                ExecStart = "${self.packages.${pkgs.stdenv.hostPlatform.system}.http-proxy}/bin/http-proxy serve";
                Restart = "on-failure";
                RestartSec = 5;
              };
            };

            # Cleanup Daemon
            vpn-proxy-cleanup = {
              description = "VPN Proxy Cleanup Daemon";
              wantedBy = [ "multi-user.target" ];
              after = [ "vpn-proxy.service" ];
              requires = [ "vpn-proxy.service" ];

              path = commonPath;
              environment = commonEnv // {
                VPN_PROXY_CLEANUP_INTERVAL = "60";
              };

              serviceConfig = commonServiceConfig // {
                Type = "simple";
                ExecStart = "${
                  self.packages.${pkgs.stdenv.hostPlatform.system}.vpn-proxy-cleanup
                }/bin/vpn-proxy-cleanup";
                Restart = "on-failure";
                RestartSec = 10;
              };
            };
          };
      };
    };
}
