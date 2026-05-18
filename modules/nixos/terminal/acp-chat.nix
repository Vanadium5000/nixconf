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
      opencodePackage = inputs.opencode.packages.${system}.opencode;
      bridgePackage = self.packages.${system}.stdio-to-ws;
      runtimePackages = cfg.extraPackages ++ [
        opencodePackage
        pkgs.git
      ];
      uiArgs = lib.escapeShellArgs [
        (toString cfg.port)
        "--bind"
        cfg.host
      ];
      bridgeArgs = lib.escapeShellArgs (
        [
          (lib.escapeShellArgs cfg.agentCommand)
          "--port"
          (toString cfg.agentPort)
          "--persist"
          "--grace-period"
          "-1"
        ]
        ++ cfg.bridgeExtraArgs
      );
    in
    {
      options.services.acp-chat = {
        enable = lib.mkEnableOption "ACP UI web client and ACP stdio-to-WebSocket bridge";

        package = lib.mkPackageOption self.packages.${system} "acp-chat" { };

        host = lib.mkOption {
          type = lib.types.str;
          default = "0.0.0.0";
          description = "Address used by the ACP UI static web server.";
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 8732;
          description = "Port used by the ACP UI static web server.";
        };

        agentPort = lib.mkOption {
          type = lib.types.port;
          default = 8733;
          description = "Port used by the ACP stdio-to-WebSocket bridge.";
        };

        openFirewall = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to open the configured UI and bridge TCP ports in the NixOS firewall.";
        };

        workDir = lib.mkOption {
          type = lib.types.path;
          default = "/var/lib/acp-chat";
          description = "State directory used as HOME and cwd for ACP UI and the bridged agent.";
        };

        agentCommand = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [
            "opencode"
            "acp"
          ];
          description = "Command run by the WebSocket bridge for each ACP agent session.";
        };

        bridgeExtraArgs = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Additional arguments passed to stdio-to-ws after the default persistent bridge flags.";
        };

        environmentFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "Optional systemd EnvironmentFile shared by the ACP UI and bridge services.";
        };

        extraPackages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [ ];
          description = "Additional packages exposed on PATH for the bridged ACP agent command.";
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
          description = "ACP UI web client for Agent Client Protocol agents";
          wantedBy = [ "multi-user.target" ];
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];

          environment.HOME = cfg.workDir;

          serviceConfig = {
            Type = "simple";
            User = "acp-chat";
            Group = "acp-chat";
            WorkingDirectory = cfg.workDir;
            ExecStart = "${lib.getExe cfg.package} ${uiArgs}";
            EnvironmentFile = lib.optional (cfg.environmentFile != null) cfg.environmentFile;
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

        systemd.services.acp-chat-agent = {
          description = "ACP stdio-to-WebSocket bridge for ACP UI";
          wantedBy = [ "multi-user.target" ];
          after = [
            "network-online.target"
            "acp-chat.service"
          ];
          wants = [ "network-online.target" ];

          # The web build of ACP UI cannot spawn stdio agents; upstream recommends
          # @rebornix/stdio-to-ws for browser/mobile clients. Source: ACP UI README
          # "Connecting from your phone or browser".
          environment.HOME = cfg.workDir;
          path = runtimePackages;

          serviceConfig = {
            Type = "simple";
            User = "acp-chat";
            Group = "acp-chat";
            WorkingDirectory = cfg.workDir;
            ExecStart = "${lib.getExe bridgePackage} ${bridgeArgs}";
            EnvironmentFile = lib.optional (cfg.environmentFile != null) cfg.environmentFile;
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

        networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [
          cfg.port
          cfg.agentPort
        ];
      };
    };
}
