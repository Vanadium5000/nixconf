{ ... }:
{
  flake.nixosModules.syncthing =
    {
      config,
      ...
    }:
    {
      # Note: use gitwatch (basically syncthing over git) for most stuff instead
      services.syncthing = {
        enable = true;
        openDefaultPorts = true; # Open ports in the firewall for Syncthing. (NOTE: this will not open syncthing gui port)

        # Set the dataDir to home
        dataDir = "/home/${config.preferences.user.username}";
        user = config.preferences.user.username;
      };

      # environment.systemPackages = with pkgs; [ syncthing ];

      # Persist necessary config files
      impermanence.home.directories = [
        # "Shared" # Shared directory
        ".local/state/syncthing" # Syncthing state
        ".config/syncthing" # Syncthing config
      ];

      impermanence.home.files = [
        ".config/syncthingtray.ini" # Syncthing tray config
      ];
    };
}
