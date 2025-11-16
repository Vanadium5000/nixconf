{
  flake.diskoConfigurations.legion5i = {
    # Use with (fill in ...):
    # nix eval .#diskoConfigurations.legion5i > /tmp/disko-config.nix
    # sudo nix run github:nix-community/disko/latest -- /tmp/disko-config.nix
    # sudo nixos-install --root /mnt --flake ...
    disko.devices = {
      disk = {
        main = {
          device = "/dev/nvme0n1";
          type = "disk";
          content = {
            type = "gpt";
            partitions = {
              boot = {
                name = "boot";
                size = "1M";
                type = "EF02"; # BIOS Boot partition type
              };
              esp = {
                name = "ESP";
                size = "500M";
                type = "EF00"; # EFI partition type
                content = {
                  type = "filesystem";
                  format = "vfat";
                  mountpoint = "/boot";
                };
              };
              swap = {
                size = "16G";
                content = {
                  type = "swap";
                  resumeDevice = true;
                  randomEncryption = true;
                  priority = 100; # Prefer to encrypt as long as we have space for it
                };
              };
              luks = {
                size = "100%";
                content = {
                  type = "luks";
                  name = "crypted";

                  # Disable settings.keyFile if you want to use interactive password entry
                  #passwordFile = "/tmp/secret.key"; # Interactive
                  settings = {
                    allowDiscards = true;
                    keyFile = "/tmp/secret.key";
                  };

                  content = {
                    type = "btrfs";
                    extraArgs = [ "-f" ]; # Override existing partition
                    # Subvolumes must set a mountpoint in order to be mounted,
                    # unless their parent is mounted
                    subvolumes = {
                      # Subvolume name is different from mountpoint
                      "/root" = {
                        mountOptions = [
                          "compress=zstd"
                        ];
                        mountpoint = "/";
                      };

                      # Parent is not mounted so the mountpoint must be set
                      "/persist" = {
                        mountOptions = [
                          "compress=zstd"
                        ];
                        mountpoint = "/persist";
                      };

                      # Parent is not mounted so the mountpoint must be set
                      "/old_roots" = {
                        mountOptions = [
                          "compress=zstd"
                        ];
                        mountpoint = "/old_roots";
                      };

                      # Parent is not mounted so the mountpoint must be set
                      # "noatime" disables the updating of access time for both files and directories
                      # so that reading a file does not update their access time, improves performance
                      "/nix" = {
                        mountOptions = [
                          "compress=zstd"
                          "noatime"
                        ];
                        mountpoint = "/nix";
                      };
                    };

                    mountpoint = "/partition-root";
                  };
                };
              };
            };
          };
        };
      };
    };
  };
}
