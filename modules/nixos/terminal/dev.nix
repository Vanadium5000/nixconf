{ self, ... }:
let
  inherit (self) secrets;
in
{
  flake.nixosModules.dev =
    { config, pkgs, ... }:
    {
      # MongoDB - a source-available, cross-platform, document-oriented database program
      services.mongodb = {
        enable = true;
        bind_ip = "0.0.0.0"; # ← This exposes it publicly
        enableAuth = true;

        # Very strong root password (do NOT hardcode)
        initialRootPasswordFile =
          pkgs.writeText "mongodb-password"
            (secrets [ "MONGODB_PASSWORD" ]).MONGODB_PASSWORD;
      };
      networking.firewall.allowedTCPPorts = [ 27017 ];

      preferences.allowedUnfree = [
        "mongodb"
        "mongodb-compass"
      ];
      # Persist DB data
      impermanence.nixos.directories = [
        {
          directory = "/var/db/mongodb";
          user = "mongodb";
          group = "mongodb";
          mode = "0700";
        }
      ];

      # Ollama - local text AIs
      services.ollama = {
        enable = true;
        acceleration = if config.nixpkgs.config.cudaSupport then "cuda" else false;
      };
      impermanence.nixos.cache.directories = [
        {
          directory = "/var/lib/private/ollama";
          user = "ollama";
          group = "ollama";
          mode = "0700";
        }
      ];

      environment.systemPackages = [ pkgs.mongodb-compass ];
    };
}
