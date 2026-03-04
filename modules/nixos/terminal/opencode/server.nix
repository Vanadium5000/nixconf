{ self, ... }:
{
  # Extends flake.nixosModules.opencode via import-tree merge
  flake.nixosModules.opencode =
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
      cfg = config.services.opencode-server;
      user = config.preferences.user.username;
    in
    {
      options.services.opencode-server = {
        enable = mkEnableOption "OpenCode headless API server";

        port = mkOption {
          type = types.port;
          default = 4096;
          description = "Port for the OpenCode HTTP API server";
        };

        hostname = mkOption {
          type = types.str;
          default = "0.0.0.0";
          description = "Hostname/IP to bind the OpenCode server to";
        };

        package = mkOption {
          type = types.package;
          default = pkgs.unstable.opencode;
          description = "OpenCode package to use";
        };
      };

      config = mkIf cfg.enable {
        systemd.services.opencode-server = {
          description = "OpenCode Headless API Server";
          wantedBy = [ "multi-user.target" ];
          wants = [ "network-online.target" ];
          after = [ "network-online.target" ];

          serviceConfig = {
            Type = "simple";
            User = user;
            Group = "users";
            ExecStart = "${cfg.package}/bin/opencode serve --port ${toString cfg.port} --hostname ${cfg.hostname}";
            Restart = "always";
            RestartSec = 5;
            WorkingDirectory = "/home/${user}";

            # Run as the configured user to access hjem-deployed config
            Environment = [
              "HOME=/home/${user}"
              "XDG_CONFIG_HOME=/home/${user}/.config"
              # Auth set only in service unit, not system-wide (avoids breaking TUI usage)
              "OPENCODE_SERVER_PASSWORD=${self.secrets.OPENCODE_SERVER_PASSWORD or ""}"
            ];
          };
        };

        # Allow remote access to the API server (protected by HTTP Basic auth)
        networking.firewall.allowedTCPPorts = [ cfg.port ];
      };
    };
}
