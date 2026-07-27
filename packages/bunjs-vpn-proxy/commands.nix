{ inputs, ... }:
{
  perSystem =
    {
      pkgs,
      self',
      ...
    }:
    let
      runtimePath = "${self'.packages.bunjs-vpn-proxy}/share/bunjs-vpn-proxy";
      mkBunCommand =
        {
          name,
          entrypoint,
          runtimePkgs,
          environment ? { },
        }:
        inputs.wrappers.lib.wrapPackage {
          inherit pkgs;
          package = pkgs.writeShellScriptBin name ''
            ${builtins.concatStringsSep "\n" (
              pkgs.lib.mapAttrsToList (key: value: "export ${key}=${value}") environment
            )}
            exec ${pkgs.bun}/bin/bun run ${runtimePath}/${entrypoint} "$@"
          '';
          inherit runtimePkgs;
        };
    in
    {
      packages.vpn-resolver = mkBunCommand {
        name = "vpn-resolver";
        entrypoint = "vpn-resolver.ts";
        runtimePkgs = [
          pkgs.bun
          pkgs.coreutils
        ];
      };

      packages.vpn-proxy = mkBunCommand {
        name = "vpn-proxy";
        entrypoint = "socks5-proxy.ts";
        environment.VPN_PROXY_NETNS_SCRIPT = "${runtimePath}/netns.sh";
        runtimePkgs = [
          pkgs.bun
          pkgs.coreutils
          pkgs.dante
          pkgs.iproute2
          pkgs.iptables
          pkgs.jq
          pkgs.libnotify
          pkgs.nftables
          pkgs.openvpn
        ];
      };

      packages.http-proxy = mkBunCommand {
        name = "http-proxy";
        entrypoint = "http-proxy.ts";
        environment.VPN_PROXY_NETNS_SCRIPT = "${runtimePath}/netns.sh";
        runtimePkgs = [
          pkgs.bun
          pkgs.coreutils
          pkgs.dante
          pkgs.iproute2
          pkgs.iptables
          pkgs.jq
          pkgs.libnotify
          pkgs.nftables
          pkgs.openvpn
        ];
      };

      packages.vpn-proxy-netns = pkgs.writeShellApplication {
        name = "vpn-proxy-netns";
        runtimeInputs = [ pkgs.bash ];
        text = ''
          exec ${pkgs.bash}/bin/bash ${runtimePath}/netns.sh "$@"
        '';
      };

      packages.vpn-proxy-cleanup = mkBunCommand {
        name = "vpn-proxy-cleanup";
        entrypoint = "cleanup.ts";
        environment.VPN_PROXY_NETNS_SCRIPT = "${runtimePath}/netns.sh";
        runtimePkgs = [
          pkgs.bun
          pkgs.coreutils
          pkgs.iproute2
          pkgs.iptables
          pkgs.nftables
        ];
      };

      packages.vpn-proxy-web = inputs.wrappers.lib.wrapPackage {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "vpn-proxy-web" ''
          export VPN_PROXY_NETNS_SCRIPT="${runtimePath}/netns.sh"
          export VPN_PROXY_WEB_DIST="${self'.packages.bunjs-vpn-proxy}/share/vpn-proxy-web/dist"
          exec ${pkgs.bun}/bin/bun ${runtimePath}/web-server.js "$@"
        '';
        runtimePkgs = [
          pkgs.bun
          pkgs.coreutils
          pkgs.curl
        ];
      };

      packages.vpn-proxy-singbox-config = mkBunCommand {
        name = "vpn-proxy-singbox-config";
        entrypoint = "singbox-config.ts";
        runtimePkgs = [
          pkgs.bun
          pkgs.coreutils
        ];
      };
    };
}
