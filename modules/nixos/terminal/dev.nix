{ ... }:
{
  flake.nixosModules.dev =
    { config, ... }:
    {
      # MongoDB - a source-available, cross-platform, document-oriented database program
      services.mongodb.enable = true;
      preferences.allowedUnfree = [
        "mongodb"
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
    };
}
