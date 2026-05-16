{ self, ... }:
{
  flake.nixosModules.ajenti =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.ajenti;
      configFile = pkgs.writeText "ajenti-config.yml" ''
        auth:
          allow_sudo: true
          emails: {}
          provider: os
          users_file: /etc/ajenti/users.yml
        bind:
          host: ${cfg.host}
          mode: tcp
          port: ${toString cfg.port}
        color: default
        language: en
        max_sessions: 9
        name: ${cfg.name}
        session_max_time: 3600
        ssl:
          enable: false
      '';
    in
    {
      options.services.ajenti = {
        enable = lib.mkEnableOption "Ajenti system administration panel";

        package = lib.mkOption {
          type = lib.types.package;
          default = self.packages.${pkgs.stdenv.hostPlatform.system}.ajenti;
          description = "Ajenti package to run.";
        };

        host = lib.mkOption {
          type = lib.types.str;
          default = "127.0.0.1";
          description = "Address Ajenti listens on; keep localhost-only when autologin is enabled.";
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 8000;
          description = "TCP port for the Ajenti web panel.";
        };

        name = lib.mkOption {
          type = lib.types.str;
          default = "${config.networking.hostName} Ajenti";
          description = "Display name shown by Ajenti.";
        };

        autologin = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Disable Ajenti-level login and trust local/Tailscale/edge-auth access controls.";
        };

        openFirewall = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to open the Ajenti port in the host firewall.";
        };
      };

      config = lib.mkIf cfg.enable {
        assertions = [
          {
            assertion = !(cfg.autologin && cfg.openFirewall);
            message = "services.ajenti.autologin must not be combined with services.ajenti.openFirewall.";
          }
        ];

        systemd.services.ajenti = {
          description = "Ajenti system administration panel";
          wantedBy = [ "multi-user.target" ];
          after = [ "network.target" ];
          path = [
            config.systemd.package
            pkgs.coreutils
            pkgs.shadow
            pkgs.util-linux
          ];
          serviceConfig = {
            # Ajenti needs root to administer systemd units, files, and terminal sessions.
            # Autologin is safe only because this module defaults to localhost + closed firewall.
            # Source: https://docs.ajenti.org/en/stable/man/run.html#cmdoption-ajenti-panel-autologin
            Type = "simple";
            ExecStart = lib.escapeShellArgs (
              [
                (lib.getExe cfg.package)
                "--config"
                configFile
              ]
              ++ lib.optional cfg.autologin "--autologin"
            );
            Restart = "on-failure";
            StateDirectory = "ajenti";
          };
        };

        networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];
      };
    };
}
