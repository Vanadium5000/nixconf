{ inputs, ... }:
{
  flake.nixosModules.common =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      inherit (lib)
        attrNames
        filterAttrs
        head
        length
        listToAttrs
        mkOption
        warn
        ;

      dedupePersistenceEntries =
        kind: entries:
        let
          pathAttr = if kind == "directory" then "directory" else "file";
          entryPath = entry: if builtins.isAttrs entry then entry.${pathAttr} else entry;
          entryName = entry: "${kind}:${entryPath entry}";
          grouped = builtins.groupBy entryName entries;
          duplicateGroups = filterAttrs (_: group: length group > 1) grouped;
          duplicatePaths = map (name: entryPath (head duplicateGroups.${name})) (attrNames duplicateGroups);
          deduped = builtins.attrValues (
            listToAttrs (
              map (entry: {
                name = entryName entry;
                value = entry;
              }) entries
            )
          );
        in
        if duplicatePaths == [ ] then
          entries
        else
          warn "impermanence: de-duplicated ${kind} persistence entries for: ${builtins.concatStringsSep ", " duplicatePaths}" deduped;

      persistOption =
        description:
        mkOption {
          default = [ ];
          type = lib.types.listOf (lib.types.either lib.types.str lib.types.attrs);
          description = description;
        };

      cfg = config.impermanence;
      username = config.preferences.user.username;
      checkoutDirectory = config.preferences.paths.configDirectory;
      persistentCheckoutDirectory = "/persist/system${checkoutDirectory}";
      escapeSystemdPath =
        path: builtins.replaceStrings [ "-" "/" ] [ "\\x2d" "-" ] (lib.removePrefix "/" path);
      checkoutMountUnit = "${escapeSystemdPath checkoutDirectory}.mount";
      checkoutBindSetup = ''
        persistent=${lib.escapeShellArg persistentCheckoutDirectory}
        checkout=${lib.escapeShellArg checkoutDirectory}

        ${pkgs.coreutils}/bin/install -d -m 0755 -o ${username} -g users "$(${pkgs.coreutils}/bin/dirname "$persistent")"
        ${pkgs.coreutils}/bin/install -d -m 0755 -o ${username} -g users "$(${pkgs.coreutils}/bin/dirname "$checkout")"

        if [ -L "$persistent" ]; then
          echo "ERROR: refusing symlinked persistent checkout '$persistent'." >&2
          exit 1
        fi

        if ! ${pkgs.util-linux}/bin/mountpoint -q "$checkout"; then
          if [ -L "$checkout" ]; then
            # The former target was a persistence symlink. Retain an unexpected
            # link durably rather than discarding the only route to its data.
            if [ "$(${pkgs.coreutils}/bin/readlink "$checkout")" != "$persistent" ]; then
              ${pkgs.coreutils}/bin/mv "$checkout" "$persistent.symlink.pre-nixos-bind.$(${pkgs.coreutils}/bin/date +%Y%m%d%H%M%S)"
            else
              ${pkgs.coreutils}/bin/rm "$checkout"
            fi
          elif [ -e "$checkout" ]; then
            if [ -d "$checkout" ] && { [ ! -e "$persistent" ] || ${pkgs.coreutils}/bin/rmdir "$persistent" 2>/dev/null; }; then
              # Seed a first migration from a real checkout without copying or
              # overwriting it; the bind below restores the original path.
              ${pkgs.coreutils}/bin/mv "$checkout" "$persistent"
            else
              ${pkgs.coreutils}/bin/mv "$checkout" "$persistent.target.pre-nixos-bind.$(${pkgs.coreutils}/bin/date +%Y%m%d%H%M%S)"
            fi
          fi

          ${pkgs.coreutils}/bin/install -d -m 0755 -o ${username} -g users "$persistent" "$checkout"
        fi
      '';
    in
    {
      imports = [
        inputs.impermanence.nixosModules.impermanence
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
        fileSystems."/persist/system".neededForBoot = true; # Needed for boot
        fileSystems."/".neededForBoot = true; # Needed for boot

        # Allow non-root users to specify the allow_other or allow_root mount options, see mount.fuse3(8).
        programs.fuse.userAllowOther = true;
        boot.tmp.cleanOnBoot = lib.mkDefault true;

        environment.persistence = {
          "/persist/system" = {
            enable = true; # NB: Defaults to true, not needed
            hideMounts = true;
            # GIO refuses trashing on hidden bind mounts unless x-gvfs-trash is
            # present; impermanence maps this option to that mount flag.
            # Source: https://github.com/nix-community/impermanence#persistent
            allowTrash = true;
            directories = dedupePersistenceEntries "directory" (
              [
                "/var/lib/bluetooth"
                "/var/lib/nixos"
                "/etc/NetworkManager/system-connections"
              ]
              ++ cfg.nixos.directories
            );
            files = dedupePersistenceEntries "file" (
              [
                "/etc/machine-id"
                {
                  file = "/var/keys/secret_file";
                  parentDirectory = {
                    mode = "u=rwx,g=,o=";
                  };
                }
              ]
              ++ cfg.nixos.files
            );
            users.${username} = {
              directories = dedupePersistenceEntries "directory" (
                [
                  "Media"
                  "Documents"
                  "Shared"

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
                ++ cfg.home.directories
              );
              files = dedupePersistenceEntries "file" cfg.home.files;
            };
          };

          "/persist/cache" = {
            enable = true; # NB: Defaults to true, not needed
            hideMounts = true;
            # Cache-backed user dirs are still visible to GUI apps, so allow
            # VSCodium/Dolphin/GIO clients to send their files to Trash too.
            # Source: https://github.com/nix-community/impermanence#persistent
            allowTrash = true;

            directories = dedupePersistenceEntries "directory" (
              [
                "/var/log"
                "/var/lib/systemd"
              ]
              ++ cfg.nixos.cache.directories
            );
            files = dedupePersistenceEntries "file" cfg.nixos.cache.files;
            users.${username} = {
              directories = dedupePersistenceEntries "directory" (
                [
                  "Downloads"
                  "Passlists"
                  ".local/share/Trash"
                ]
                ++ cfg.home.cache.directories
              );
              files = dedupePersistenceEntries "file" cfg.home.cache.files;
            };
          };
        };

        # DynamicUser services such as llama.cpp keep writable state under /var/lib/private.
        # Use tmpfiles type "d" so an impermanent root creates the parent as 0700 instead
        # of relying on type "z", which only adjusts paths that already exist. This keeps
        # the parent secure without persisting every DynamicUser private state directory.
        # Source: https://www.freedesktop.org/software/systemd/man/latest/tmpfiles.d.html
        systemd.tmpfiles.rules = [
          "d /var/lib/private 0700 root root -"
        ];

        system.activationScripts.nixconf-checkout-bind = {
          deps = [ "users" ];
          text = checkoutBindSetup;
        };

        # Bind the checkout so editors see a normal writable tree. This also
        # keeps checkout-sourced managed file binds available before local-fs
        # mounts their individual configuration files.
        fileSystems."${checkoutDirectory}" = {
          device = persistentCheckoutDirectory;
          fsType = "none";
          options = [
            "bind"
            "nofail"
            "x-systemd.requires-mounts-for=/persist/system"
          ];
        };

        systemd.services.nixconf-checkout-bind = {
          description = "Prepare persistent nixconf checkout bind mount";
          before = [ checkoutMountUnit ];
          requiredBy = [ checkoutMountUnit ];
          after = [ "persist-system.mount" ];
          path = [
            pkgs.coreutils
            pkgs.util-linux
          ];
          script = checkoutBindSetup;
          unitConfig.DefaultDependencies = false;
          serviceConfig.Type = "oneshot";
        };

        # systemd stage-1 does not support postResumeCommands; run the Btrfs
        # root rotation before systemd-fstab-generator mounts /sysroot. Keep
        # PATH on initrd /bin:/sbin: pkgs.util-linux's mount is a split-output
        # symlink, and stage-1 service.path expands bare /bin to the invalid
        # /bin/bin. Logs showed rollback-root otherwise succeeded with
        # "mount: command not found" and left the previous root active.
        # Sources: impermanence README Btrfs subvolume recipe; nixpkgs
        # boot.initrd.systemd.services/initrdBin option docs; bootup(7).
        boot.initrd.systemd.initrdBin = [
          pkgs.btrfs-progs
          pkgs.coreutils
          pkgs.findutils
          pkgs.util-linux
        ];

        boot.initrd.systemd.services.rollback-root = {
          description = "Rotate impermanent Btrfs root subvolume";
          wantedBy = [ "initrd-root-fs.target" ];
          before = [ "sysroot.mount" ];
          unitConfig.DefaultDependencies = false;
          serviceConfig = {
            Type = "oneshot";
            TimeoutSec = 30;
          };
          after = [ "initrd-root-device.target" ];
          script = ''
            export PATH=/bin:/sbin

            cleanup() {
                umount /btrfs_tmp || true
                rmdir /btrfs_tmp || true
            }

            rollback_root() {
                set -eu

                mkdir -p /btrfs_tmp
                mount -o rw,subvolid=5 /dev/${cfg.volumeGroup}/root /btrfs_tmp
                trap cleanup EXIT

                mkdir -p /btrfs_tmp/old_roots

                if [ -e /btrfs_tmp/root ]; then
                    if [ "$(stat -c %i /btrfs_tmp/root)" -ne 256 ]; then
                        echo "/btrfs_tmp/root exists but is not a Btrfs subvolume; keeping it for boot" >&2
                        return 0
                    fi

                    new_root="/btrfs_tmp/root-new"
                    counter=0
                    while [ -e "$new_root" ]; do
                        counter=$((counter + 1))
                        new_root="/btrfs_tmp/root-new-$counter"
                    done
                    btrfs subvolume create "$new_root"

                    timestamp=$(stat -c %Y /btrfs_tmp/root)
                    old_root="/btrfs_tmp/old_roots/$timestamp"
                    counter=0
                    while [ -e "$old_root" ]; do
                        counter=$((counter + 1))
                        old_root="/btrfs_tmp/old_roots/$timestamp-$counter"
                    done

                    if ! mv /btrfs_tmp/root "$old_root"; then
                        btrfs subvolume delete "$new_root" || true
                        return 1
                    fi

                    if ! mv "$new_root" /btrfs_tmp/root; then
                        mv "$old_root" /btrfs_tmp/root || true
                        btrfs subvolume delete "$new_root" || true
                        return 1
                    fi
                else
                    btrfs subvolume create /btrfs_tmp/root
                fi

                delete_subvolume_recursively() {
                    IFS=$'\n'

                    # If we accidentally end up with a file or directory under old_roots,
                    # the code will enumerate all subvolumes under the main volume.
                    # We don't want to remove everything under true main volume. Only
                    # proceed if this path is a btrfs subvolume (inode=256).
                    if [ "$(stat -c %i "$1")" -ne 256 ]; then return; fi

                    for i in $(btrfs subvolume list -o "$1" | cut -f 9- -d ' '); do
                        delete_subvolume_recursively "/btrfs_tmp/$i"
                    done
                    btrfs subvolume delete "$1"
                }

                # Pruning old snapshots is maintenance, not boot-critical.
                if [ -d /btrfs_tmp/old_roots ]; then
                    find /btrfs_tmp/old_roots -mindepth 1 -maxdepth 1 -mtime +30 -print | while IFS= read -r i; do
                        delete_subvolume_recursively "$i" || true
                    done
                fi
            }

            rollback_root
          '';
        };
      };
    };
}
