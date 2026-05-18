{ inputs, self, ... }:
{
  flake.nixosModules.acp-chat =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      cfg = config.services.acp-chat;
      system = pkgs.stdenv.hostPlatform.system;
      format = pkgs.formats.json { };
      settingsFile = format.generate "acp-chat-settings.json" {
        # acp-chat loads VS Code-compatible `agent_servers` from .vscode/settings.json
        # while walking upward from cwd. Source: acp-chat/server/src/acp/external_settings.ts.
        agent_servers = cfg.agentServers;
        # Keep upstream built-in agent discovery unless explicitly disabled; the VS Code
        # setting key is declared in upstream package.json under contributes.configuration.
        "acp.includeBuiltInAgents" = cfg.includeBuiltInAgents;
      };
      opencodePackage = inputs.opencode.packages.${system}.opencode;
      runtimePackages = cfg.extraPackages ++ [
        opencodePackage
        pkgs.nodejs
        pkgs.git
        pkgs.openssl
      ];
    in
    {
      options.services.acp-chat = {
        enable = lib.mkEnableOption "acp-chat browser UI for Agent Client Protocol agents";

        package = lib.mkPackageOption self.packages.${system} "acp-chat" { };

        host = lib.mkOption {
          type = lib.types.str;
          default = "0.0.0.0";
          description = "Address passed to ACP_CHAT_HOST.";
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 8732;
          description = "Port passed to ACP_CHAT_PORT.";
        };

        openFirewall = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to open the configured TCP port in the NixOS firewall.";
        };

        workDir = lib.mkOption {
          type = lib.types.path;
          default = "/var/lib/acp-chat";
          description = "State directory used as HOME and cwd so acp-chat can discover .vscode/settings.json.";
        };

        connectTimeoutMs = lib.mkOption {
          type = lib.types.ints.positive;
          default = 600000;
          description = "ACP_CONNECT_TIMEOUT_MS value used while waiting for agent connections.";
        };

        environmentFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "Optional systemd EnvironmentFile for overriding generated acp-chat environment.";
        };

        agentServers = lib.mkOption {
          type = format.type;
          default = {
            opencode = {
              command = "opencode";
              args = [ "acp" ];
            };
          };
          description = "Declarative ACP agent_servers written to the VS Code settings file acp-chat reads.";
        };

        includeBuiltInAgents = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether acp-chat should include upstream built-in ACP agent presets.";
        };

        extraPackages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [ ];
          description = "Additional packages exposed on PATH for declarative ACP agent commands.";
        };
      };

      config = lib.mkIf cfg.enable {
        users.groups.acp-chat = { };
        users.users.acp-chat = {
          isSystemUser = true;
          group = "acp-chat";
          home = cfg.workDir;
          createHome = true;
        };

        systemd.services.acp-chat = {
          description = "acp-chat browser UI for Agent Client Protocol agents";
          wantedBy = [ "multi-user.target" ];
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];

          # Upstream reads ACP_CHAT_HOST/PORT/AUTH_TOKEN and ACP_CONNECT_TIMEOUT_MS
          # in acp-chat/server/src/index.ts; auth is generated outside the Nix store.
          environment = {
            ACP_CHAT_HOST = cfg.host;
            ACP_CHAT_PORT = toString cfg.port;
            ACP_CONNECT_TIMEOUT_MS = toString cfg.connectTimeoutMs;
            HOME = cfg.workDir;
          };

          # Use the service-level `path` option instead of environment.PATH so
          # NixOS can merge its default systemd helper PATH without conflicts.
          # Source: nixos/modules/system/boot/systemd.nix defines PATH globally.
          path = runtimePackages;

          preStart = ''
            set -eu
            install -d -m 0700 -o acp-chat -g acp-chat '${cfg.workDir}' '${cfg.workDir}/.vscode'

            if [ ! -f '${cfg.workDir}/acp-chat.env' ]; then
              token="$(${pkgs.openssl}/bin/openssl rand -hex 32)"
              umask 077
              printf 'ACP_CHAT_AUTH_TOKEN=%s\n' "$token" > '${cfg.workDir}/acp-chat.env'
            fi

            ln -sfn '${settingsFile}' '${cfg.workDir}/.vscode/settings.json'
            chown -h acp-chat:acp-chat '${cfg.workDir}/.vscode/settings.json'
            chown acp-chat:acp-chat '${cfg.workDir}/acp-chat.env'
            chmod 0600 '${cfg.workDir}/acp-chat.env'
          '';

          serviceConfig = {
            Type = "simple";
            User = "acp-chat";
            Group = "acp-chat";
            WorkingDirectory = cfg.workDir;
            ExecStart = lib.getExe cfg.package;
            EnvironmentFile = [
              "-${cfg.workDir}/acp-chat.env"
            ]
            ++ lib.optional (cfg.environmentFile != null) cfg.environmentFile;
            Restart = "on-failure";
            RestartSec = "5s";
            StateDirectory = "acp-chat";
            StateDirectoryMode = "0700";
            NoNewPrivileges = true;
            PrivateTmp = true;
            ProtectSystem = "strict";
            ReadWritePaths = [ cfg.workDir ];
          };
        };

        impermanence.nixos.directories = [
          {
            directory = cfg.workDir;
            user = "acp-chat";
            group = "acp-chat";
            mode = "0700";
          }
        ];

        networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];
      };
    };
}
