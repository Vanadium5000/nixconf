{ inputs, ... }:
{
  flake.nixosModules.common =
    {
      lib,
      config,
      ...
    }:
    let
      inherit (lib)
        mkOption
        ;

      persistOption =
        description:
        mkOption {
          default = [ ];
          type = lib.types.listOf (lib.types.either lib.types.str lib.types.attrs);
          description = description;
        };

      cfg = config.impermanence;
      username = config.preferences.user.username;
    in
    {
      imports = [
        inputs.impermanence.nixosModules.impermanence

        # Tool for retroactive persistence in NixOS configurations
        inputs.persist-retro.nixosModules.persist-retro
      ];

      options.impermanence = {
        enable = mkOption {
          description = "Enable impermanence for NixOS";
          type = lib.types.bool;
          default = true;
        };

        volumeGroup = mkOption {
          default = "pool";
          description = ''
            Btrfs volume group name
          '';
        };

        nixos = {
          directories = persistOption "System directories to persist";
          files = persistOption "System files to persist";

          # For non-essential but high-volumes of data
          cache = {
            directories = persistOption "System cache directories to persist";
            files = persistOption "System cache files to persist";
          };
        };

        home = {
          directories = persistOption "User directories to persist";
          files = persistOption "User files to persist";

          # For non-essential but high-volumes of data
          cache = {
            directories = persistOption "User cache directories to persist";
            files = persistOption "User cache files to persist";
          };
        };
      };

      config = lib.mkIf cfg.enable {
        fileSystems."/persist".neededForBoot = true; # Needed for boot

        # Allow non-root users to specify the allow_other or allow_root mount options, see mount.fuse3(8).
        programs.fuse.userAllowOther = true;
        boot.tmp.cleanOnBoot = lib.mkDefault true;

        environment.persistence = {
          "/persist/system" = {
            enable = true; # NB: Defaults to true, not needed
            hideMounts = true;
            directories = [
              "/var/log"
              "/var/lib/bluetooth"
              "/var/lib/nixos"
              "/var/lib/systemd/coredump"
              "/etc/NetworkManager/system-connections"
            ]
            ++ cfg.nixos.directories;
            files = [
              "/etc/machine-id"
              {
                file = "/var/keys/secret_file";
                parentDirectory = {
                  mode = "u=rwx,g=,o=";
                };
              }
            ]
            ++ cfg.nixos.files;
            users.${username} = {
              directories = [
                "Media"
                "Documents"
                "Downloads"
                "Shared"
                "nixconf"

                # Credential storage
                {
                  directory = ".gnupg";
                  mode = "0700";
                }
                {
                  directory = ".ssh";
                  mode = "0700";
                }
                {
                  directory = ".local/share/keyrings";
                  mode = "0700";
                }
                {
                  directory = ".local/share/password-store";
                  mode = "0700";
                }
              ]
              ++ cfg.home.directories;
              files = [
              ]
              ++ cfg.home.files;
            };
          };

          "/persist/cache" = {
            enable = true; # NB: Defaults to true, not needed
            hideMounts = true;

            directories = cfg.nixos.cache.directories;
            files = cfg.nixos.cache.files;
            users.${username} = {
              directories = [
                ".cache/personalive"
                "Passlists"
              ]
              ++ cfg.home.cache.directories;
              files = cfg.home.cache.files;
            };
          };
        };

        # Fix "/var/lib/private" has too permissive permissions (0755 rather than 0700) errors
        systemd.tmpfiles.rules = [
          "d /var/lib/private 0700 root root -"
        ];

        boot.initrd.postResumeCommands = lib.mkAfter ''
          mkdir /btrfs_tmp
          mount /dev/${cfg.volumeGroup}/root /btrfs_tmp
          if [[ -e /btrfs_tmp/root ]]; then
              mkdir -p /btrfs_tmp/old_roots
              timestamp=$(date --date="@$(stat -c %Y /btrfs_tmp/root)" "+%Y-%m-%-d_%H:%M:%S")
              mv /btrfs_tmp/root "/btrfs_tmp/old_roots/$timestamp"
          fi

          delete_subvolume_recursively() {
              IFS=$'\n'

              # If we accidentally end up with a file or directory under old_roots,
              # the code will enumerate all subvolumes under the main volume.
              # We don't want to remove everything under true main volume. Only
              # proceed if this path is a btrfs subvolume (inode=256).
              if [ $(stat -c %i "$1") -ne 256 ]; then return; fi

              for i in $(btrfs subvolume list -o "$1" | cut -f 9- -d ' '); do
                  delete_subvolume_recursively "/btrfs_tmp/$i"
              done
              btrfs subvolume delete "$1"
          }

          for i in $(find /btrfs_tmp/old_roots/ -maxdepth 1 -mtime +30); do
              delete_subvolume_recursively "$i"
          done

          btrfs subvolume create /btrfs_tmp/root
          umount /btrfs_tmp
        '';
      };
    };
}
