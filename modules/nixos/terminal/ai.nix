{ ... }:
{
  flake.nixosModules.ai =
    { pkgs, ... }:
    {
      services.wyoming.faster-whisper = {
        package = pkgs.wyoming-faster-whisper;

        servers.default = {
          enable = true;
          uri = "tcp://0.0.0.0:10300";
          model = "small";
          language = "en";
          device = "auto";
        };
      };

      # Open firewall for local access
      networking.firewall.allowedTCPPorts = [ 10300 ];
    };
}
