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
      runtimeConfigFile = "/var/lib/ajenti/config.yml";
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

        environment.etc."ajenti".source = "/var/lib/ajenti/etc";

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
            ExecStartPre = pkgs.writeShellScript "ajenti-pre-start" ''
              set -eu

              install -d -m 0750 /var/lib/ajenti/etc

              install -m 0600 -T ${configFile} ${runtimeConfigFile}

              if [ ! -e /var/lib/ajenti/etc/users.yml ]; then
                install -m 0600 /dev/null /var/lib/ajenti/etc/users.yml
                printf 'users: null\n' > /var/lib/ajenti/etc/users.yml
              fi

              if [ ! -e /var/lib/ajenti/etc/smtp.yml ]; then
                install -m 0600 /dev/null /var/lib/ajenti/etc/smtp.yml
                cat > /var/lib/ajenti/etc/smtp.yml <<'YAML'
              smtp:
                password: ""
                port: starttls
                server: ""
                user: ""
              YAML
              fi

              if [ ! -e /var/lib/ajenti/etc/tfa.yml ]; then
                install -m 0600 /dev/null /var/lib/ajenti/etc/tfa.yml
                printf 'users: {}\n' > /var/lib/ajenti/etc/tfa.yml
              fi

              chmod 0600 /var/lib/ajenti/etc/users.yml /var/lib/ajenti/etc/smtp.yml /var/lib/ajenti/etc/tfa.yml
            '';
            ExecStart = lib.escapeShellArgs (
              [
                (lib.getExe cfg.package)
                "--config"
                runtimeConfigFile
              ]
              ++ lib.optionals cfg.autologin [
                # Upstream intentionally refuses --autologin unless debug/verbose
                # mode is set, so include -v while keeping access restricted by
                # localhost binding, closed firewall, and edge/Tailscale auth.
                # Source: ajenti-panel entrypoint: `Autologin is a dangerous option...`
                "-v"
                "--autologin"
              ]
            );
            Restart = "on-failure";
            StateDirectory = "ajenti";
            LogsDirectory = "ajenti";
          };
        };

        networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];
      };
    };
}
