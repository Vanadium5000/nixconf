{ ... }:
{
  flake.nixosModules.zeroclaw =
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
      cfg = config.services.zeroclaw;

      defaultConfig = pkgs.writeText "zeroclaw-default-config.toml" ''
        # ZeroClaw configuration — edit freely, not managed by Nix after initial creation
        # See: https://github.com/zeroclaw-labs/zeroclaw

        [gateway]
        host = "127.0.0.1"
        port = 3100  # Avoids conflict with my-website-backend on port 3000

        [security]
        workspace_only = true
        autonomy = "Supervised"
        # allowed_commands = ["git", "cargo", "ls", "cat", "rg"]
        # forbidden_paths = ["/etc", "/root"]
      '';
    in
    {
      options.services.zeroclaw = {
        enable = mkEnableOption "ZeroClaw autonomous AI agent daemon";

        package = mkOption {
          type = types.package;
          default = pkgs.unstable.zeroclaw;
          description = "ZeroClaw package to use";
        };
      };

      config = mkIf cfg.enable {
        # Dedicated system user with restricted access
        users.users.zeroclaw = {
          isSystemUser = true;
          group = "zeroclaw";
          home = "/var/lib/zeroclaw";
          description = "ZeroClaw AI agent service user";
        };
        users.groups.zeroclaw = { };

        # Bootstrap mutable config.toml on first activation only
        # Never overwrites — user edits config.toml directly for
        # allowedCommands, autonomyLevel, API keys, etc.
        system.activationScripts.zeroclaw-bootstrap = {
          text = ''
            ZCDIR="/var/lib/zeroclaw"
            mkdir -p "$ZCDIR/.zeroclaw/workspace"
            if [ ! -f "$ZCDIR/.zeroclaw/config.toml" ]; then
              cp ${defaultConfig} "$ZCDIR/.zeroclaw/config.toml"
              chmod 644 "$ZCDIR/.zeroclaw/config.toml"
            fi
            chown -R zeroclaw:zeroclaw "$ZCDIR"
            chmod 700 "$ZCDIR"
          '';
        };

        systemd.services.zeroclaw = {
          description = "ZeroClaw Autonomous AI Agent Daemon";
          wantedBy = [ "multi-user.target" ];
          wants = [ "network-online.target" ];
          after = [ "network-online.target" ];

          serviceConfig = {
            Type = "simple";
            User = "zeroclaw";
            Group = "zeroclaw";
            ExecStart = "${cfg.package}/bin/zeroclaw daemon";
            Restart = "always";
            RestartSec = 10;

            # State management
            StateDirectory = "zeroclaw";
            WorkingDirectory = "/var/lib/zeroclaw";

            # HOME resolves ~/.zeroclaw/ inside the state directory
            Environment = [
              "HOME=/var/lib/zeroclaw"
            ];

            # Sandbox — strict isolation but allow command execution
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            NoNewPrivileges = true;
            PrivateDevices = true;
            ProtectKernelTunables = true;
            ProtectControlGroups = true;
            ReadWritePaths = [ "/var/lib/zeroclaw" ];

            # Allow @process for zeroclaw's built-in command execution
            SystemCallFilter = [
              "@system-service"
              "@process"
            ];
          };
        };

        # Persist config, workspace, and memory across reboots
        impermanence.nixos.directories = [
          {
            directory = "/var/lib/zeroclaw";
            user = "zeroclaw";
            group = "zeroclaw";
            mode = "0700";
          }
        ];
      };
    };
}
