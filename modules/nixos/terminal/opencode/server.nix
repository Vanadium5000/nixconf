{ self, inputs, ... }:
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
      homeDirectory = config.preferences.paths.homeDirectory;
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
          default = inputs.opencode.packages.${pkgs.stdenv.hostPlatform.system}.default;
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
            WorkingDirectory = homeDirectory;

            # Run as the configured user to access hjem-deployed config.
            # nginx already gates the public endpoint, so duplicating auth here
            # turns browser access into a confusing double-login flow.
            Environment = [
              "HOME=${homeDirectory}"
              "XDG_CONFIG_HOME=${homeDirectory}/.config"
            ];
          };
        };

        # Allow remote access to the API server (protected by HTTP Basic auth)
        networking.firewall.allowedTCPPorts = [ cfg.port ];
      };
    };
}
