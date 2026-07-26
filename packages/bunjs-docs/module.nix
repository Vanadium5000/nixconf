{ self, ... }:
{
  flake.nixosModules.nixconf-docs =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (lib)
        mkEnableOption
        mkIf
        mkOption
        types
        ;
      cfg = config.services.nixconf-docs;
      system = pkgs.stdenv.hostPlatform.system;
    in
    {
      options.services.nixconf-docs = {
        enable = mkEnableOption "static Nixconf Docusaurus documentation";

        host = mkOption {
          type = types.str;
          default = "127.0.0.1";
          description = "Address nginx listens on for the generated docs site.";
        };

        port = mkOption {
          type = types.port;
          default = 8090;
          description = "Port for the generated docs site.";
        };

        openFirewall = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to open the docs port in the firewall.";
        };

        package = mkOption {
          type = types.package;
          default = self.packages.${system}.bunjs-docs;
          description = "Built static Docusaurus documentation artifact.";
        };
      };

      config = mkIf cfg.enable {
        services.nginx = {
          enable = true;
          virtualHosts.nixconf-docs = {
            listen = [
              {
                addr = cfg.host;
                port = cfg.port;
              }
            ];
            root = "${cfg.package}/share/nixconf-docs";
            locations."/" = {
              index = "index.html";
              tryFiles = "$uri $uri/ /index.html";
            };
          };
        };

        networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];
      };
    };
}
