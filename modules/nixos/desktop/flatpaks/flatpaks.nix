{ inputs, ... }:
{
  flake.nixosModules.firefox =
    { ... }:
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
          # Monitoring
          "io.missioncenter.MissionCenter" # System monitoring
          "net.nokyan.Resources" # System monitoring

          # Configuration software
          "com.github.wwmm.easyeffects" # Pipewire/audio effects Manager
          "com.github.tchx84.Flatseal" # Review & modify permissions of Flatpaks
          "io.github.nokse22.inspector" # View lots of system information

          "io.gitlab.adhami3310.Impression" # Creates bootable drives
          "org.libreoffice.LibreOffice" # LibeOffice suite
          "org.gimp.GIMP" # GIMP - Image Editor
          "org.inkscape.Inkscape" # Inkscape - Vector Graphics Editor

          "org.vinegarhq.Sober" # Sober
        ];
      };

      # Persist flatpak apps
      impermanence.nixos.cache.directories = [ "/var/lib/flatpak" ];

      # Persist flatpak storage
      impermanence.home.cache.directories = [
        ".var/app" # Persist flatpak apps
        ".local/share/flatpak"
      ];

      # TODO: ^^^ Make flatpak persistence more selective/fix this ^^^
    };
}
