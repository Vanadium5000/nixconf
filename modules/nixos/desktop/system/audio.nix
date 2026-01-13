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
        jack.enable = true;
      };

      environment.systemPackages = with pkgs; [
        pavucontrol
        libnotify # For desktop notifications
        mpc # MPD CLI client
      ];

      # Music Player Daemon
      services.mpd = {
        enable = true;
        user = user; # Required so the musicDirectory can be accessed
        musicDirectory = "/home/${user}/Shared/Music";
        # Make MPD only start when something actually tries to connect to it
        startWhenNeeded = true;

        extraConfig = ''
          audio_output {
            type "pipewire"
            name "My PipeWire Output"
          }
        '';
      };

      systemd.services.mpd.environment = {
        # https://gitlab.freedesktop.org/pipewire/pipewire/-/issues/609
        XDG_RUNTIME_DIR = "/run/user/${toString config.users.users.${user}.uid}"; # User-id must match above user. MPD will look inside this directory for the PipeWire socket.
      };
    };
}
