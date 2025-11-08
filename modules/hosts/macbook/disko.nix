{
  flake.diskoConfigurations.macbook = {
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
              root = {
                size = "100%";
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
                  swap = {
                    size = "16G";
                    content = {
                      type = "swap";
                      resumeDevice = true;
                    };
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
