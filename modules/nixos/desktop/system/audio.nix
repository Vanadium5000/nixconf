{
  flake.nixosModules.audio =
    { pkgs, config, ... }:
    let
      user = config.preferences.user.username;
    in
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
        libnotify # For desktop notifications
      ];

      # Music Player Daemon
      services.mpd = {
        enable = true;
        musicDirectory = "/home/${user}/Shared/Music";
        # Make MPD only start when something actually tries to connect to it
        startWhenNeeded = true;
      };
    };
}
