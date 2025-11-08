{ inputs, ... }:
{
  flake.nixosModules.dev =
    { pkgs, ... }:
    {
      services.mongodb.enable = true;

      # Custom option
      allowedUnfree = [
        "mongodb"
      ];

      # Persist data
      impermanence.nixos.directories = [
        {
          directory = "/var/db/mongodb";
          user = "mongodb";
          group = "mongodb";
          mode = "0700";
        }
      ];
    };
}
