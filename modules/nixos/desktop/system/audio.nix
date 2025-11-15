{
  flake.nixosModules.audio =
    { pkgs, ... }:
    {
      # rtkit is optional but recommended
      security.rtkit.enable = true;

      # Disable PulseAudio
      services.pulseaudio.enable = false;

      # Pipewire & wireplumber configuration
      services.pipewire = {
        enable = true;
        alsa.enable = true;
        alsa.support32Bit = true;
        pulse.enable = true;
        wireplumber.enable = true;

        # If you want to use JACK applications, uncomment this
        #jack.enable = true;
      };

      environment.systemPackages = with pkgs; [
        pavucontrol
        swww # Wallpaper daemon for Wayland
      ];
    };
}
