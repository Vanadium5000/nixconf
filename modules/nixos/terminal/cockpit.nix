{ ... }:
{
  flake.nixosModules.cockpit =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.cockpit-autologin;
      cockpitPackage = config.services.cockpit.package;
      cockpitWs = "${cockpitPackage}/libexec/cockpit-ws";
      cockpitBridge = "${cockpitPackage}/bin/cockpit-bridge";
    in
    {
      options.services.cockpit-autologin = {
        enable = lib.mkEnableOption "unauthenticated Cockpit system administration panel";

        host = lib.mkOption {
          type = lib.types.str;
          default = "127.0.0.1";
          description = "Address Cockpit listens on; use 0.0.0.0 only behind trusted network/auth controls.";
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 9090;
          description = "TCP port for the Cockpit web panel.";
        };

        openFirewall = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to open the Cockpit port in the host firewall.";
        };

        superuser = lib.mkOption {
          type = lib.types.enum [
            "none"
            "pkexec"
          ];
          default = "pkexec";
          description = "Cockpit superuser bridge mode.";
        };
      };

      config = lib.mkIf cfg.enable {
        assertions = [
          {
            assertion = !(cfg.host == "0.0.0.0" && cfg.openFirewall);
            message = "services.cockpit-autologin.host = 0.0.0.0 must not be combined with services.cockpit-autologin.openFirewall.";
          }
        ];

        services.cockpit = {
          enable = true;
          openFirewall = false;
          showBanner = false;
          allowed-origins = [
            "https://*.my-website.space"
            "http://*.my-website.space"
            "http://localhost:${toString cfg.port}"
            "http://127.0.0.1:${toString cfg.port}"
          ];
          settings.WebService = {
            AllowUnencrypted = true;
            LoginTo = false;
            AllowMultiHost = false;
          };
        };

        systemd.sockets.cockpit = {
          wantedBy = lib.mkForce [ ];
          listenStreams = lib.mkForce [ ];
        };

        systemd.services.cockpit-autologin = {
          description = "Unauthenticated Cockpit web console";
          documentation = [
            "man:cockpit-ws(8)"
            "https://cockpit-project.org/guide/latest/cockpit-ws.8.html"
          ];
          wantedBy = [ "multi-user.target" ];
          after = [ "network.target" ];
          path = [
            config.systemd.package
            pkgs.coreutils
            pkgs.polkit
          ];
          environment = {
            COCKPIT_SUPERUSER = cfg.superuser;
          };
          serviceConfig = {
            # --local-session intentionally skips Cockpit's login screen; public access is gated by
            # the existing Traefik forward-auth middleware and LAN access relies on closed firewall + Tailscale.
            # Source: cockpit-ws(8), --local-session warning requires external TCP isolation.
            Type = "simple";
            ExecStart = lib.escapeShellArgs [
              cockpitWs
              "--no-tls"
              "--address"
              cfg.host
              "--port"
              (toString cfg.port)
              "--local-session=${cockpitBridge}"
            ];
            Restart = "on-failure";
          };
        };

        networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];
      };
    };
}
