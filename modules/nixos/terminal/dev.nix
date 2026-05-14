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

        # Very strong root password (do NOT hardcode)
        initialRootPasswordFile = pkgs.writeText "mongodb-password" (secrets.MONGODB_PASSWORD);

        # Use upstream's current Community Edition package. If an existing DB was
        # last opened by MongoDB 7.x, first run while still on 7.x:
        #   nix shell nixpkgs#mongosh -c mongosh --eval 'db.adminCommand({setFeatureCompatibilityVersion: "7.0", confirm: true})'
        # Then rebuild with this package, start MongoDB 8, and finalize with:
        #   mongosh --eval 'db.adminCommand({setFeatureCompatibilityVersion: "8.0", confirm: true})'
        package = pkgs.mongodb-ce;
        # Optional but recommended:
        dbpath = "/var/db/mongodb";
      };

      preferences.allowedUnfree = [
        "mongodb-ce"
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
        package =
          if config.nixpkgs.config.cudaSupport then pkgs.unstable.ollama-cuda else pkgs.unstable.ollama;
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

      environment.systemPackages = [
        pkgs.mongodb-compass
        pkgs.openssl # encryption
      ];

    };
}
