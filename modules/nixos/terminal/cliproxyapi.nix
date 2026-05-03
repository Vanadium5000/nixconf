{ ... }:
{
  flake.nixosModules.cliproxyapi =
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
      cfg = config.services.cliproxyapi;

      optionalManagementEnv = lib.optional (
        cfg.managementKey != null
      ) "MANAGEMENT_PASSWORD=${cfg.managementKey}";

      defaultConfig = pkgs.writeText "cliproxyapi-default-config.yaml" ''
        # CLIProxyAPI configuration — edit freely, not managed by Nix after initial creation
        # Changes are hot-reloaded without restart
        # See: https://github.com/router-for-me/CLIProxyAPI
        # Management UI: http://localhost:${toString cfg.port}/management.html

        host: "${cfg.host}"
        port: ${toString cfg.port}
        auth-dir: "/var/lib/cliproxyapi/auths"
        logging-to-file: true

        remote-management:
          allow-remote: true
          secret-key: "change-me"  # Auto-hashed on startup

        usage-statistics-enabled: true

        # TLS (enable if exposing without reverse proxy)
        # tls:
        #   enable: false
        #   cert: "/path/to/cert.pem"
        #   key: "/path/to/key.pem"

        # pprof debugging — keep bound to localhost
        # pprof:
        #   enable: false
        #   addr: "127.0.0.1:6060"
      '';
    in
    {
      options.services.cliproxyapi = {
        enable = mkEnableOption "CLIProxyAPI — OpenAI-compatible API wrapping AI CLIs";

        port = mkOption {
          type = types.port;
          default = 8317;
          description = "Port for the CLIProxyAPI HTTP server";
        };

        host = mkOption {
          type = types.str;
          default = "0.0.0.0";
          description = "Host/IP to bind the CLIProxyAPI server to";
        };

        package = mkOption {
          type = types.package;
          default = pkgs.customPackages.cliproxyapi;
          description = "CLIProxyAPI package to use";
        };

        openFirewall = mkOption {
          type = types.bool;
          default = true;
          description = "Whether to open the CLIProxyAPI port in the firewall";
        };

        managementKey = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Plain management key exposed to CLIProxyAPI through MANAGEMENT_PASSWORD";
        };
      };

      config = mkIf cfg.enable {
        # Dedicated system user with restricted access
        users.users.cliproxyapi = {
          isSystemUser = true;
          group = "cliproxyapi";
          home = "/var/lib/cliproxyapi";
          description = "CLIProxyAPI service user";
        };
        users.groups.cliproxyapi = { };

        # Bootstrap mutable config.yaml on first activation only
        # Never overwrites — user edits config.yaml directly for provider setup
        # CLIProxyAPI supports hot-reloading: changes take effect without restart
        system.activationScripts.cliproxyapi-bootstrap = {
          text = ''
            CPDIR="/var/lib/cliproxyapi"
            mkdir -p "$CPDIR/auths" "$CPDIR/logs"
            if [ ! -f "$CPDIR/config.yaml" ]; then
              cp ${defaultConfig} "$CPDIR/config.yaml"
              chmod 644 "$CPDIR/config.yaml"
            fi
            chown -R cliproxyapi:cliproxyapi "$CPDIR"
            chmod 700 "$CPDIR"
          '';
        };

        systemd.services.cliproxyapi = {
          description = "CLIProxyAPI — OpenAI-compatible API Server";
          wantedBy = [ "multi-user.target" ];
          wants = [ "network-online.target" ];
          after = [ "network-online.target" ];

          serviceConfig = {
            Type = "simple";
            User = "cliproxyapi";
            Group = "cliproxyapi";
            # Reads ./config.yaml from WorkingDirectory
            ExecStart = "${cfg.package}/bin/cliproxyapi";
            Restart = "on-failure";
            RestartSec = 10;

            # State management
            StateDirectory = "cliproxyapi";
            WorkingDirectory = "/var/lib/cliproxyapi";

            # MANAGEMENT_PASSWORD is accepted by upstream as a runtime-only
            # management key, avoiding dependence on a mutable config.yaml hash.
            # Source: https://github.com/router-for-me/CLIProxyAPI/blob/v6.10.1/internal/api/handlers/management/handler.go
            Environment = [
              "HOME=/var/lib/cliproxyapi"
            ]
            ++ optionalManagementEnv;

            # Sandbox — strict isolation, data confined to state dir
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            NoNewPrivileges = true;
            PrivateDevices = true;
            ReadWritePaths = [ "/var/lib/cliproxyapi" ];
          };
        };

        # Persist config, auth tokens, and logs across reboots
        impermanence.nixos.directories = [
          {
            directory = "/var/lib/cliproxyapi";
            user = "cliproxyapi";
            group = "cliproxyapi";
            mode = "0700";
          }
        ];

        networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];
      };
    };
}
