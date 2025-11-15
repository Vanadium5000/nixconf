{
  flake.nixosModules.hyprsunset =
    # This is a NixOS module to enable a systemd user service for hyprsunset.
    # It configures hyprsunset to adjust screen temperature based on time of day:
    # - 6000K from 6:00 AM to 7:15 PM (default/neutral)
    # - 2500K from 7:15 PM to 10:30 PM (warm)
    # - 1000K from 10:30 PM to 6:00 AM (very warm)
    # The service kills any previous instances before starting, restarts automatically
    # every 60 seconds if it stops (unlimited attempts), and generates the config file.

    {
      config,
      lib,
      pkgs,
      ...
    }:

    with lib;

    let
      cfg = config.services.hyprsunset; # Configuration namespace for this module
    in
    {
      # Define the enable option for the service
      options.services.hyprsunset = {
        enable = mkEnableOption "Enable hyprsunset blue light filter service";
      };

      config = mkIf cfg.enable {
        # Install the hyprsunset package system-wide
        environment.systemPackages = [ pkgs.hyprsunset ];

        # Define the systemd user service for hyprsunset
        systemd.user.services.hyprsunset = {
          # Service description
          description = "Hyprsunset - Blue light filter for Hyprland";

          # Start when the graphical session is ready
          wantedBy = [ "graphical-session.target" ];

          # Stop when the graphical session stops
          partOf = [ "graphical-session.target" ];

          # Service configuration
          serviceConfig = {
            # Run hyprsunset as the main process
            ExecStart = "${pkgs.hyprsunset}/bin/hyprsunset";

            # Always restart the service if it stops, regardless of exit code
            Restart = "always";

            # Wait 60 seconds before restarting
            RestartSec = "60s";

            # Simple service type (foreground process)
            Type = "simple";
          };

          # Pre-start script: Kill previous instances and generate config file
          preStart = ''
            # Kill any existing hyprsunset processes to avoid conflicts
            pkill hyprsunset || true

            # Ensure the config directory exists
            mkdir -p $HOME/.config/hypr

            # Generate the hyprsunset config file with time-based profiles
            cat > $HOME/.config/hypr/hyprsunset.conf <<EOF
            # Hyprsunset configuration
            # Profiles activate at specified times and set screen temperature

            # Morning/daytime profile: Neutral temperature
            profile {
              time = 06:00
              temperature = 6000
            }

            # Evening profile: Warm temperature starting at 7:15 PM
            profile {
              time = 19:15
              temperature = 2500
            }

            # Night profile: Very warm temperature starting at 10:30 PM
            profile {
              time = 22:30
              temperature = 1000
            }
            EOF
          '';
        };
      };
    };
}
