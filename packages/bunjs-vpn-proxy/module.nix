{ self, ... }:
{
  flake.nixosModules.vpn-proxy-service =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    let
      inherit (lib) mkIf mkOption types;
      cfg = config.services.vpn-proxy;
      packageSet = self.packages.${pkgs.stdenv.hostPlatform.system};
    in
    {
      options.services.vpn-proxy = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Enable SOCKS5, HTTP CONNECT, and VPN proxy web services.";
        };
        port = mkOption {
          type = types.port;
          default = 10800;
          description = "SOCKS5 proxy port.";
        };
        httpPort = mkOption {
          type = types.port;
          default = 10801;
          description = "HTTP CONNECT proxy port.";
        };
        webUiPort = mkOption {
          type = types.port;
          default = 10802;
          description = "VPN proxy web interface port.";
        };
        vpnDir = mkOption {
          type = types.str;
          default = config.preferences.paths.vpnDirectory;
          description = "Directory containing OpenVPN configurations.";
        };
        idleTimeout = mkOption {
          type = types.int;
          default = 300;
          description = "Base idle timeout in seconds before a VPN namespace is cleaned up.";
        };
        randomRotation = mkOption {
          type = types.int;
          default = 300;
          description = "Seconds between random VPN rotations.";
        };
        bindAddress = mkOption {
          type = types.str;
          default = "0.0.0.0";
          description = "Address on which the proxy listeners bind.";
        };
      };

      config = mkIf cfg.enable {
        preferences.commandHelp.commands = [
          {
            command = "vpn-proxy";
            description = "Run the VPN SOCKS5 proxy command-line server and management interface.";
            usage = "vpn-proxy [serve|tool] [args]";
            package = packageSet.vpn-proxy;
          }
          {
            command = "http-proxy";
            description = "Run the legacy VPN HTTP CONNECT proxy command-line server.";
            usage = "http-proxy [command]";
            package = packageSet.http-proxy;
          }
          {
            command = "vpn-resolver";
            description = "Resolve and inspect VPN profile names and endpoints.";
            usage = "vpn-resolver {list|list-json|resolve|match|server-ip} [args]";
            package = packageSet.vpn-resolver;
          }
          {
            command = "vpn-proxy-netns";
            description = "Operate the VPN proxy network-namespace helper.";
            usage = "vpn-proxy-netns [command] [args]";
            package = packageSet.vpn-proxy-netns;
          }
          {
            command = "vpn-proxy-cleanup";
            description = "Run the VPN proxy namespace cleanup process.";
            usage = "vpn-proxy-cleanup [args]";
            package = packageSet.vpn-proxy-cleanup;
          }
          {
            command = "vpn-proxy-web";
            description = "Run the local VPN proxy web management interface.";
            usage = "vpn-proxy-web [args]";
            package = packageSet.vpn-proxy-web;
          }
          {
            command = "vpn-proxy-singbox-config";
            description = "Generate the sing-box configuration used by VPN proxy services.";
            usage = "vpn-proxy-singbox-config [args]";
            package = packageSet.vpn-proxy-singbox-config;
          }
        ];

        environment.systemPackages = [
          packageSet.vpn-resolver
          packageSet.vpn-proxy
          packageSet.http-proxy
          packageSet.vpn-proxy-netns
          packageSet.vpn-proxy-cleanup
          packageSet.vpn-proxy-web
          packageSet.vpn-proxy-singbox-config
        ];

        impermanence.nixos.directories = [
          {
            directory = "/var/lib/vpn-proxy";
            user = "root";
            group = "root";
            mode = "0700";
          }
        ];

        systemd.tmpfiles.rules = [
          "d /run/netns 0755 root root -"
          "d /etc/netns 0755 root root -"
          "d /var/lib/vpn-proxy 0700 root root -"
        ];

        systemd.services =
          let
            stateDir = "/var/lib/vpn-proxy";
            runtimePath = "${packageSet.bunjs-vpn-proxy}/share/bunjs-vpn-proxy";
            commonPath = [
              pkgs.bash
              pkgs.coreutils
              pkgs.curl
              pkgs.dante
              pkgs.findutils
              pkgs.gawk
              pkgs.gnugrep
              pkgs.iproute2
              pkgs.iptables
              pkgs.jq
              pkgs.libnotify
              pkgs.nftables
              pkgs.openvpn
              pkgs.procps
              pkgs.sing-box
              pkgs.socat
              pkgs.util-linux
            ];
            commonEnv = {
              VPN_DIR = cfg.vpnDir;
              VPN_PROXY_PORT = toString cfg.port;
              VPN_HTTP_PROXY_PORT = toString cfg.httpPort;
              VPN_PROXY_BIND_ADDRESS = cfg.bindAddress;
              VPN_PROXY_IDLE_TIMEOUT = toString cfg.idleTimeout;
              VPN_PROXY_RANDOM_ROTATION = toString cfg.randomRotation;
              XDG_RUNTIME_DIR = "/run/user/1000";
              DBUS_SESSION_BUS_ADDRESS = "unix:path=/run/user/1000/bus";
            };
            commonServiceConfig = {
              NoNewPrivileges = false;
              ProtectSystem = "full";
              ProtectHome = "read-only";
              PrivateTmp = true;
              ReadWritePaths = [
                "/dev/shm"
                "/run/netns"
                "/var/run/netns"
                "/etc/netns"
                stateDir
                "/run/user/1000"
              ];
            };
            run = entrypoint: "${pkgs.bun}/bin/bun run ${runtimePath}/${entrypoint}";
          in
          {
            vpn-proxy = {
              description = "VPN SOCKS5 Proxy Server";
              wantedBy = [ "multi-user.target" ];
              after = [ "network.target" ];
              path = commonPath;
              environment = commonEnv // {
                VPN_PROXY_NETNS_SCRIPT = "${runtimePath}/netns.sh";
                VPN_PROXY_SINGBOX_CONFIG = "${stateDir}/sing-box.json";
              };
              serviceConfig = commonServiceConfig // {
                Type = "simple";
                ExecStart = "${run "socks5-proxy.ts"} serve";
                Restart = "on-failure";
                RestartSec = 5;
              };
            };

            vpn-proxy-singbox = {
              description = "VPN Proxy sing-box frontend";
              wantedBy = [ "multi-user.target" ];
              after = [
                "network.target"
                "vpn-proxy.service"
              ];
              path = commonPath;
              environment = commonEnv;
              serviceConfig = commonServiceConfig // {
                Type = "simple";
                ExecStartPre = run "singbox-config.ts";
                ExecStart = "${pkgs.sing-box}/bin/sing-box run -c ${stateDir}/sing-box.json";
                Restart = "on-failure";
                RestartSec = 5;
              };
            };

            vpn-proxy-cleanup = {
              description = "VPN Proxy Cleanup Daemon";
              wantedBy = [ "multi-user.target" ];
              after = [ "vpn-proxy.service" ];
              requires = [ "vpn-proxy.service" ];
              path = commonPath;
              environment = commonEnv // {
                VPN_PROXY_CLEANUP_INTERVAL = "60";
                VPN_PROXY_NETNS_SCRIPT = "${runtimePath}/netns.sh";
              };
              serviceConfig = commonServiceConfig // {
                Type = "simple";
                ExecStart = run "cleanup.ts";
                Restart = "on-failure";
                RestartSec = 10;
              };
            };

            vpn-proxy-web = {
              description = "VPN Proxy Web Management UI";
              wantedBy = [ "multi-user.target" ];
              after = [
                "network.target"
                "vpn-proxy.service"
                "vpn-proxy-singbox.service"
              ];
              wants = [
                "vpn-proxy.service"
                "vpn-proxy-singbox.service"
              ];
              path = commonPath;
              environment = commonEnv // {
                VPN_PROXY_API_KEY = self.secrets.VPN_PROXY_API_KEY or "";
                VPN_PROXY_NETNS_SCRIPT = "${runtimePath}/netns.sh";
                VPN_PROXY_WEB_DIST = "${packageSet.bunjs-vpn-proxy}/share/vpn-proxy-web/dist";
                VPN_PROXY_WEB_PORT = toString cfg.webUiPort;
              };
              serviceConfig = commonServiceConfig // {
                Type = "simple";
                ReadWritePaths = commonServiceConfig.ReadWritePaths ++ [ cfg.vpnDir ];
                ExecStart = "${pkgs.bun}/bin/bun ${runtimePath}/web-server.js";
                Restart = "on-failure";
                RestartSec = 5;
              };
            };
          };
      };
    };
}
