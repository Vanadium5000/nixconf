{ ... }:
{
  flake.nixosModules.cpa-usage-keeper =
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
      cfg = config.services.cpa-usage-keeper;

      optionalEnv = lib.optional (cfg.loginPassword != null) "LOGIN_PASSWORD=${cfg.loginPassword}";
    in
    {
      options.services.cpa-usage-keeper = {
        enable = mkEnableOption "CPA Usage Keeper — persistent CLIProxyAPI usage dashboard";

        package = mkOption {
          type = types.package;
          default = pkgs.customPackages.cpa-usage-keeper;
          description = "CPA Usage Keeper package to use";
        };

        port = mkOption {
          type = types.port;
          default = 8080;
          description = "Port for the CPA Usage Keeper HTTP server";
        };

        openFirewall = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to open the CPA Usage Keeper port in the firewall";
        };

        workDir = mkOption {
          type = types.path;
          default = "/var/lib/cpa-usage-keeper";
          description = "Persistent work directory for the SQLite database, logs, and backups";
        };

        cpaBaseUrl = mkOption {
          type = types.str;
          default = "http://127.0.0.1:8317";
          description = "Base URL for the CLIProxyAPI instance to read usage data from";
        };

        cpaManagementKey = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "CLIProxyAPI management key used to read usage data";
        };

        authEnabled = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to enable CPA Usage Keeper's built-in login form";
        };

        loginPassword = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Login password required when built-in auth is enabled";
        };

        timezone = mkOption {
          type = types.str;
          default = "Europe/London";
          description = "Business timezone used for daily aggregation and cleanup";
        };

        usageSyncMode = mkOption {
          type = types.enum [
            "auto"
            "redis"
            "legacy_export"
          ];
          default = "auto";
          description = "Usage sync mode selected by CPA Usage Keeper";
        };
      };

      config = mkIf cfg.enable {
        assertions = [
          {
            assertion = cfg.cpaManagementKey != null;
            message = "services.cpa-usage-keeper.cpaManagementKey must be set from the CPA management secret";
          }
          {
            assertion = cfg.authEnabled -> cfg.loginPassword != null;
            message = "services.cpa-usage-keeper.loginPassword must be set when built-in auth is enabled";
          }
        ];

        users.users.cpa-usage-keeper = {
          isSystemUser = true;
          group = "cpa-usage-keeper";
          home = cfg.workDir;
          description = "CPA Usage Keeper service user";
        };
        users.groups.cpa-usage-keeper = { };

        systemd.services.cpa-usage-keeper = {
          description = "CPA Usage Keeper — CLIProxyAPI usage dashboard";
          wantedBy = [ "multi-user.target" ];
          wants = [
            "network-online.target"
            "cliproxyapi.service"
          ];
          after = [
            "network-online.target"
            "cliproxyapi.service"
          ];

          serviceConfig = {
            Type = "simple";
            User = "cpa-usage-keeper";
            Group = "cpa-usage-keeper";
            ExecStart = "${cfg.package}/bin/cpa-usage-keeper";
            Restart = "on-failure";
            RestartSec = 10;

            # v1.3.2 derives app.db, logs/, and backups/ from WORK_DIR, so keep
            # the working directory identical to the persisted state path.
            # Source: https://github.com/Willxup/cpa-usage-keeper/releases/tag/v1.3.2
            StateDirectory = "cpa-usage-keeper";
            WorkingDirectory = cfg.workDir;

            Environment = [
              "APP_PORT=${toString cfg.port}"
              "AUTH_ENABLED=${lib.boolToString cfg.authEnabled}"
              "CPA_BASE_URL=${cfg.cpaBaseUrl}"
              "CPA_MANAGEMENT_KEY=${cfg.cpaManagementKey}"
              "HOME=${cfg.workDir}"
              "TZ=${cfg.timezone}"
              "USAGE_SYNC_MODE=${cfg.usageSyncMode}"
              "WORK_DIR=${cfg.workDir}"
            ]
            ++ optionalEnv;

            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            NoNewPrivileges = true;
            PrivateDevices = true;
            ReadWritePaths = [ cfg.workDir ];
          };
        };

        impermanence.nixos.directories = [
          {
            directory = cfg.workDir;
            user = "cpa-usage-keeper";
            group = "cpa-usage-keeper";
            mode = "0700";
          }
        ];

        networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];
      };
    };
}
