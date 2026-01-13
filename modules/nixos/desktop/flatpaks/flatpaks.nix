{ inputs, ... }:
{
  flake.nixosModules.firefox =
    { pkgs, ... }:
    let
      run-flatpak-instance = pkgs.writeShellScriptBin "run-flatpak-instance" ''
        # Usage: ./run_sober_instance.sh [instance_number] [app_id]
        # 
        # instance_number: Required, e.g., 1, 2, 3... (creates isolated instance)
        # app_id: Optional, defaults to org.vinegarhq.Sober
        #
        # This script creates a separate home directory for each instance
        # allowing multiple isolated runs of Sober (Roblox client on Linux via Flatpak)
        # to support multiple accounts simultaneously.

        set -euo pipefail

        if [[ $# -lt 1 ]]; then
            echo "Usage: $0 <instance_number> [app_id]"
            echo "Example: $0 1"
            echo "         $0 2 org.vinegarhq.Sober"
            exit 1
        fi

        INSTANCE_NUM="$1"
        APP_ID="''${2:-org.vinegarhq.Sober}"

        INSTANCE_DIR="$HOME/flatpak-instances/''${APP_ID}-''${INSTANCE_NUM}"

        mkdir -p "$INSTANCE_DIR"

        echo "Launching $APP_ID instance $INSTANCE_NUM with isolated home: $INSTANCE_DIR"

        HOME="$INSTANCE_DIR" flatpak run "$APP_ID"
      '';
    in
    {
      imports = [
        inputs.nix-flatpak.nixosModules.nix-flatpak # Install flatpaks declaratively
      ];
      # By default nix-flatpak will add the flathub remote
      services.flatpak = {
        enable = true;

        update = {
          auto = {
            enable = true;
            onCalendar = "weekly"; # Default value
          };
          onActivation = false;
        };

        uninstallUnmanaged = true;
        uninstallUnused = true; # Automatically clean up stale packages

        packages = [
          # Configuration software
          "com.github.wwmm.easyeffects" # Pipewire/audio effects Manager
          "com.github.tchx84.Flatseal" # Review & modify permissions of Flatpaks

          "org.kde.haruna" # Video player
          "org.kde.ktorrent" # Torrent client
          "org.kde.filelight" # Disk Usage
          "org.kde.isoimagewriter" # Creates bootable drives
          "org.libreoffice.LibreOffice" # LibeOffice suite
          "org.gimp.GIMP" # GIMP - Image Editor
          "org.inkscape.Inkscape" # Inkscape - Vector Graphics Editor

          # "org.vinegarhq.Sober" # Sober
        ];
      };

      # Add the run-flatpak-instance script to packages
      environment.systemPackages = [
        # run-flatpak-instance
      ];

      # Persist flatpak apps
      impermanence.nixos.cache.directories = [ "/var/lib/flatpak" ];

      # Persist flatpak storage
      impermanence.home.cache.directories = [
        ".var/app" # Persist flatpak apps
        ".local/share/flatpak"
        "flatpak-instances"
      ];
      # TODO: ^^^ Make flatpak persistence more selective/fix this ^^^
    };
}
