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
      };

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

      # Virtualisation
      virtualisation = {
        podman = {
          enable = true;
          # Create a `docker` alias for podman, to use it as a drop-in replacement
          dockerCompat = true;
          # Required for containers under podman-compose to be able to talk to each other.
          defaultNetwork.settings.dns_enabled = true;

          networkSocket.openFirewall = true;
        };

        libvirtd.enable = true;
        oci-containers.backend = "podman";
      };
      # Use nvidia with podman/docker - https://discourse.nixos.org/t/nvidia-docker-container-runtime-doesnt-detect-my-gpu/51336
      hardware.nvidia-container-toolkit.enable = config.nixpkgs.config.cudaSupport;
    };
}
