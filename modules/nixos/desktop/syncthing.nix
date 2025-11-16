{ ... }:
{
  flake.nixosModules.syncthing =
    {
      pkgs,
      ...
    }:
    {
      # Note: use gitwatch (basically syncthing over git) for most stuff instead
      services.syncthing = {
        enable = true;
        openDefaultPorts = true; # Open ports in the firewall for Syncthing. (NOTE: this will not open syncthing gui port)
      };

      environment.systemPackages = with pkgs; [ syncthing ];

      # Persist necessary config files
      impermanence.home.directories = [
        # "Shared" # Shared directory
        ".local/state/syncthing" # Syncthing state/config
      ];

      impermanence.home.files = [
        ".config/syncthingtray.ini" # Syncthing tray config
      ];
    };
}
