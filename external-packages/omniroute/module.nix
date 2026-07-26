{ ... }:
{
  flake.nixosModules.omniroute =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    let
      inherit (lib)
        mkEnableOption
        mkOption
        mkIf
        types
        ;
      cfg = config.services.omniroute;
      envFile = "${cfg.workDir}/omniroute.env";
      optionalEnv = lib.optionals (cfg.publicBaseUrl != null) [
        "BASE_URL=http://${cfg.host}:${toString cfg.port}"
        "CORS_ORIGIN=${cfg.publicBaseUrl}"
        "NEXT_PUBLIC_BASE_URL=${cfg.publicBaseUrl}"
      ];
    in
    {
      options.services.omniroute = {
        enable = mkEnableOption "OmniRoute - OpenAI-compatible AI gateway";

        package = mkOption {
          type = types.package;
          default = pkgs.customPackages.omniroute;
          description = "OmniRoute package to use";
        };

        host = mkOption {
          type = types.str;
          default = "127.0.0.1";
          description = "Address to bind the OmniRoute HTTP server to";
        };

        port = mkOption {
          type = types.port;
          default = 20128;
          description = "Port for the OmniRoute dashboard and OpenAI-compatible API";
        };

        publicBaseUrl = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Canonical public URL used for dashboard links and OAuth callbacks";
        };

        workDir = mkOption {
          type = types.path;
          default = "/var/lib/omniroute";
          description = "Persistent data directory for OmniRoute state, SQLite data, and logs";
        };

        authCookieSecure = mkOption {
          type = types.bool;
          default = false;
          description = "Whether OmniRoute should mark dashboard auth cookies as HTTPS-only";
        };

        initialPassword = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = ''
            Initial dashboard password used when OmniRoute is first initialized. If
            unset, a random password is generated on first start.
          '';
        };

        requireApiKey = mkOption {
          type = types.bool;
          default = false;
          description = "Whether OmniRoute should require API keys for /v1 proxy requests";
        };

        memoryMb = mkOption {
          type = types.ints.positive;
          default = 512;
          description = "Node.js heap limit in MiB for the OmniRoute server process";
        };

        openFirewall = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to open the OmniRoute port in the firewall";
        };
      };

      config = mkIf cfg.enable {
        users.users.omniroute = {
          isSystemUser = true;
          group = "omniroute";
          home = cfg.workDir;
          description = "OmniRoute service user";
        };
        users.groups.omniroute = { };

        systemd.services.omniroute = {
          description = "OmniRoute - OpenAI-compatible AI Gateway";
          wantedBy = [ "multi-user.target" ];
          wants = [ "network-online.target" ];
          after = [ "network-online.target" ];

          serviceConfig = {
            Type = "simple";
            User = "omniroute";
            Group = "omniroute";
            ExecStart = "${cfg.package}/bin/omniroute --no-open";
            Restart = "on-failure";
            RestartSec = 10;

            # DATA_DIR controls the SQLite DB, logs, backups, and bootstrap env.
            # Source: https://github.com/diegosouzapw/OmniRoute/blob/v3.7.9/docs/ENVIRONMENT.md
            StateDirectory = "omniroute";
            StateDirectoryMode = "0700";
            WorkingDirectory = cfg.workDir;

            Environment = [
              "APP_LOG_TO_FILE=true"
              "AUTH_COOKIE_SECURE=${lib.boolToString cfg.authCookieSecure}"
              "DATA_DIR=${cfg.workDir}"
              "HOME=${cfg.workDir}"
              "NODE_ENV=production"
              # 3.8.48+ reads OMNIROUTE_SERVER_HOST; keep OMNIROUTE_HOST for older patched builds.
              # Source: https://github.com/diegosouzapw/OmniRoute/blob/v3.8.48/bin/cli/commands/serve.mjs
              "OMNIROUTE_SERVER_HOST=${cfg.host}"
              "OMNIROUTE_HOST=${cfg.host}"
              "OMNIROUTE_MEMORY_MB=${toString cfg.memoryMb}"
              "PORT=${toString cfg.port}"
              "REQUIRE_API_KEY=${lib.boolToString cfg.requireApiKey}"
            ]
            ++ optionalEnv;
            # Keep bootstrap secrets out of generated Nix/systemd unit text; the
            # preStart hook creates this root-readable path on the target host.
            # Source: https://github.com/diegosouzapw/OmniRoute/blob/v3.7.9/docs/ENVIRONMENT.md
            EnvironmentFile = "-${envFile}";

            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            NoNewPrivileges = true;
            PrivateDevices = true;
            ReadWritePaths = [ cfg.workDir ];
          };

          preStart = ''
              set -euo pipefail
              umask 077

              # Generate bootstrap secrets only once so dashboard sessions, encrypted
              # provider credentials, and API keys survive service restarts.
              #
              # OmniRoute persists these values in DATA_DIR, so they must not be regenerated
              # after the first successful start.
              if [ ! -f ${lib.escapeShellArg envFile} ]; then
                ${
                  if cfg.initialPassword != null then
                    ''
                      # Use the administrator-supplied bootstrap password.
                      initial_password=${lib.escapeShellArg cfg.initialPassword}
                    ''
                  else
                    ''
                      # No bootstrap password was configured, so generate one.
                      initial_password="$(${pkgs.openssl}/bin/openssl rand -base64 24)"
                    ''
                }

                cat > ${lib.escapeShellArg envFile} <<EOF
            INITIAL_PASSWORD=$initial_password
            JWT_SECRET=$(${pkgs.openssl}/bin/openssl rand -base64 48)
            API_KEY_SECRET=$(${pkgs.openssl}/bin/openssl rand -hex 32)
            EOF

                chmod 600 ${lib.escapeShellArg envFile}
              fi
          '';
        };

        impermanence.nixos.directories = [
          {
            directory = cfg.workDir;
            user = "omniroute";
            group = "omniroute";
            mode = "0700";
          }
        ];

        networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];
      };
    };
}
