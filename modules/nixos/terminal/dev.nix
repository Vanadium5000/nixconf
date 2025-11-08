{ ... }:
{
  flake.nixosModules.dev =
    { ... }:
    {
      services.mongodb.enable = true;

      # Custom option
      preferences.allowedUnfree = [
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
