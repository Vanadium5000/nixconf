{ ... }:
{
  flake.nixosModules.virtualisation =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    {
      programs.virt-manager.enable = true;

      # Fixes for podman, the process of creation of DevContainers' containers to become stuck at the "Please select an image URL" step
      # Global `/etc/containers/registries.conf`
      environment.etc."containers/registries.conf".text = lib.mkForce ''
        [registries.search]
        registries = ['docker.io']
      '';
      # User-scoped `~/.config/containers/registries`
      hjem.users.${config.preferences.user.username}.files."containers/registries.conf".text = ''
        [registries.search]
        registries = ['docker.io']
      '';

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

      # Add 'newuidmap' and 'sh' to the PATH for users' Systemd units.
      # Required for Rootless podman.
      # https://discourse.nixos.org/t/rootless-podman-setup-with-home-manager/57905
      #systemd.user.extraConfig = ''
      #  DefaultEnvironment="PATH=/run/current-system/sw/bin:/run/wrappers/bin:${lib.makeBinPath [pkgs.bash]}"
      #'';

      environment.systemPackages = with pkgs; [
        dive # look into docker image layers
        podman-tui # status of containers in the terminal
        podman-compose # start group of containers for dev

        qemu # virtualisation

        nur.repos.ataraxiasjel.waydroid-script # For installing libndk & other tools (for running ARM64 Android apps on x64)
      ];

      virtualisation.waydroid = {
        enable = true;
        package = pkgs.waydroid-nftables;
      };

      # Pesist the waydroid data
      impermanence.home.cache.directories = [
        ".local/share/waydroid"
        ".cache/waydroid-script"

        # Podman & other VM Data
        ".local/share/containers"
        ".config/libvirt"
      ];
      impermanence.nixos.cache.directories = [
        "/var/lib/waydroid"

        # Podman & other VM Data
        "/var/lib/containers"
        "/var/lib/libvirt"
        "/etc/libvirt/qemu"
      ];
    };
}
