{ inputs, ... }:
{
  flake.nixosModules.firefox =
    { pkgs, ... }:
    let
      run-flatpak-instance = pkgs.writeShellScriptBin "run-flatpak-instance" ''
        set -euo pipefail

        show_help() {
          cat <<EOF
        Usage: $(basename "$0") <APP_ID> <INSTANCE_ID> [ARGS...]

        Runs a Flatpak application with an isolated home directory, allowing multiple
        instances of the same application to run simultaneously with different configurations.

        Arguments:
          APP_ID       The Flatpak application ID (e.g., org.mozilla.firefox)
          INSTANCE_ID  A unique identifier for this instance (e.g., 1, 2, "work", "private")
          ARGS         Optional arguments to pass to the Flatpak application

        Example:
          $(basename "$0") org.mozilla.firefox work
          $(basename "$0") org.telegram.desktop 2
        EOF
        }

        if [[ "''${1:-}" == "-h" || "''${1:-}" == "--help" ]]; then
          show_help
          exit 0
        fi

        if [[ $# -lt 2 ]]; then
          echo "Error: Missing required arguments." >&2
          show_help
          exit 1
        fi

        APP_ID="$1"
        INSTANCE_ID="$2"
        shift 2

        # Sanitize INSTANCE_ID to prevent directory traversal or weird names
        if [[ ! "$INSTANCE_ID" =~ ^[a-zA-Z0-9_-]+$ ]]; then
          echo "Error: INSTANCE_ID must only contain alphanumeric characters, underscores, and hyphens." >&2
          exit 1
        fi

        INSTANCE_DIR="$HOME/flatpak-instances/''${APP_ID}-''${INSTANCE_ID}"

        echo "Starting $APP_ID (Instance: $INSTANCE_ID)..."
        echo "Instance Directory: $INSTANCE_DIR"

        mkdir -p "$INSTANCE_DIR"

        # Run with isolated home
        HOME="$INSTANCE_DIR" flatpak run "$APP_ID" "$@"
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
          "org.libreoffice.LibreOffice" # LibreOffice suite - also used by libreoffice-mcp for headless doc operations
          "org.gimp.GIMP" # GIMP - Image Editor
          "org.inkscape.Inkscape" # Inkscape - Vector Graphics Editor

          # "org.vinegarhq.Sober" # Sober
        ];
      };

      # Add the run-flatpak-instance script to packages
      environment.systemPackages = [
        run-flatpak-instance
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
