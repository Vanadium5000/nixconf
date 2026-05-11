{ self, ... }:
{
  flake.nixosModules.virtualisation =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    let
      selfpkgs = self.packages.${pkgs.stdenv.hostPlatform.system};
    in
    {
      programs.virt-manager.enable = true;

      virtualisation = {
        docker = {
          enable = true;
          daemon.settings.live-restore = false;
        };
        podman = {
          enable = false;
          dockerCompat = false;
        };

        libvirtd.enable = true;
        oci-containers.backend = "docker";
      };

      # Use nvidia with Docker - https://discourse.nixos.org/t/nvidia-docker-container-runtime-doesnt-detect-my-gpu/51336
      hardware.nvidia-container-toolkit.enable = config.nixpkgs.config.cudaSupport;

      environment.systemPackages = with pkgs; [
        dive # look into docker image layers
        docker-compose # start group of containers for dev

        qemu # virtualisation

        selfpkgs.waydroid-script # Keep this local so update-pkgs can track the exact commit pinned by this flake.
      ];

      virtualisation.waydroid = {
        enable = true;
        package = pkgs.waydroid-nftables;
      };

      # Pesist the waydroid data
      impermanence.home.cache.directories = [
        ".local/share/waydroid"
        ".cache/waydroid-script"

        # VM Data
        ".config/libvirt"
      ];
      impermanence.nixos.cache.directories = [
        "/var/lib/waydroid"

        # Docker & other VM Data
        "/var/lib/docker"
        "/var/lib/libvirt"
        "/etc/libvirt/qemu"
      ];
    };
}
