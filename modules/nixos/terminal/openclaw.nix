{ ... }:
{
  flake.nixosModules.openclaw =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    let
      inherit (lib)
        mkEnableOption
        mkIf
        mkOption
        types
        ;
      cfg = config.services.openclaw;
    in
    {
      options.services.openclaw = {
        enable = mkEnableOption "OpenClaw AI assistant gateway";

        package = mkOption {
          type = types.package;
          default = pkgs.unstable.openclaw;
          description = "Official OpenClaw package from nixpkgs unstable";
        };

        port = mkOption {
          type = types.port;
          default = 3100;
          description = "Port for the localhost-only OpenClaw gateway";
        };

        stateDir = mkOption {
          type = types.str;
          default = "/var/lib/openclaw";
          description = "Persisted OpenClaw home directory used for normal onboarding and runtime state";
        };
      };

      config = mkIf cfg.enable {
        users.users.openclaw = {
          isSystemUser = true;
          group = "openclaw";
          home = cfg.stateDir;
          description = "OpenClaw gateway service user";
        };
        users.groups.openclaw = { };

        # Keep the runtime home persistent and fully user-managed so OpenClaw's
        # normal onboarding flow can create ~/.openclaw state without Nix trying
        # to own or overwrite its mutable config afterwards.
        system.activationScripts.openclaw-bootstrap = {
          text = ''
            install -d -m 0750 -o openclaw -g openclaw "${cfg.stateDir}"
          '';
        };

        systemd.services.openclaw = {
          description = "OpenClaw Gateway";
          wantedBy = [ "multi-user.target" ];
          wants = [ "network-online.target" ];
          after = [ "network-online.target" ];

          serviceConfig = {
            Type = "simple";
            User = "openclaw";
            Group = "openclaw";
            ExecStart = "${cfg.package}/bin/openclaw gateway --port ${toString cfg.port}";
            Restart = "on-failure";
            RestartSec = 10;

            StateDirectory = "openclaw";
            WorkingDirectory = cfg.stateDir;

            Environment = [
              "HOME=${cfg.stateDir}"
              "OPENCLAW_HOME=${cfg.stateDir}"
              "OPENCLAW_GATEWAY_BIND=loopback"
            ];

            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            NoNewPrivileges = true;
            PrivateDevices = true;
            ReadWritePaths = [ cfg.stateDir ];
          };
        };

        # Persist the entire OpenClaw home so onboarding-created config, memory,
        # skills, plugins, and workspace survive ephemeral-root reboots.
        impermanence.nixos.directories = [
          {
            directory = cfg.stateDir;
            user = "openclaw";
            group = "openclaw";
            mode = "0750";
          }
        ];
      };
    };
}
