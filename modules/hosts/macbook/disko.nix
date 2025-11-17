{
  flake.diskoConfigurations.macbook = {
    # Use with (fill in ...):
    # nix eval .#diskoConfigurations.macbook > /tmp/disko-config.nix
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
              # LUKS-LVM
              # https://github.com/nix-community/disko/blob/master/example/luks-lvm.nix
              luks = {
                size = "100%";
                content = {
                  type = "luks";
                  name = "crypted";
                  extraOpenArgs = [ ];
                  settings = {
                    # if you want to use the key for interactive login be sure there is no trailing newline
                    # for example use `echo -n "password" > /tmp/secret.key`
                    # keyFile = "/tmp/secret.key";
                    allowDiscards = true;
                  };
                  # additionalKeyFiles = [ "/tmp/additionalSecret.key" ];
                  content = {
                    type = "lvm_pv";
                    vg = "pool";
                  };
                };
              };
            };
          };
        };
      };
      lvm_vg = {
        pool = {
          type = "lvm_vg";
          lvs = {
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

                  "/swap" = {
                    mountpoint = "/.swapvol";
                    swap.swapfile.size = "16G";
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
}
