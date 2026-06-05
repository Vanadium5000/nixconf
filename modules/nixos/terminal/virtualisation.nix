{ self, ... }:
{
  flake.nixosModules.virtualisation =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      selfpkgs = self.packages.${pkgs.stdenv.hostPlatform.system};
    in
    {
      config = {
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

        environment.systemPackages =
          with pkgs;
          [
            dive # look into docker image layers
            docker-compose # start group of containers for dev

            qemu # virtualisation
          ]
          ++ lib.optionals config.preferences.profiles.desktop.enable [
            selfpkgs.waydroid-script # Keep this local so update-pkgs can track the exact commit pinned by this flake.
          ];

        virtualisation.waydroid = lib.mkIf config.preferences.profiles.desktop.enable {
          enable = true;
          package = pkgs.waydroid-nftables;
        };

        # Waydroid bind-mounts Android /data from the host user tree, but Android
        # services require numeric Android UIDs inside that tree; keystore2 aborts
        # and restarts Android if persistence ever rewrites /data/misc/keystore to
        # the host user. Keep the targeted subtree on Android keystore UID 1017.
        systemd.tmpfiles.rules = lib.mkIf config.preferences.profiles.desktop.enable [
          "z /home/${config.preferences.user.username}/.local/share/waydroid/data/misc/keystore 0700 1017 1017 -"
          "Z /home/${config.preferences.user.username}/.local/share/waydroid/data/misc/keystore - 1017 1017 -"
        ];

        # Persist Waydroid's Android /data as system state: Android numeric UIDs
        # must survive untouched, while user persistence can chown entries to the
        # host user and break core services such as keystore2; desktop entries are
        # user-owned launchers regenerated from Android apps, so keep them in home.
        impermanence.home.cache.directories = [
          ".local/share/applications"
          ".cache/waydroid-script"

          # VM Data
          ".config/libvirt"
        ];
        impermanence.nixos.cache.directories = [
          "/var/lib/waydroid"
          {
            directory = "/home/${config.preferences.user.username}/.local/share/waydroid";
            user = "root";
            group = "root";
            mode = "0755";
          }

          # Docker & other VM Data
          "/var/lib/docker"
          "/var/lib/libvirt"
          "/etc/libvirt/qemu"
        ];
      };
    };
}
