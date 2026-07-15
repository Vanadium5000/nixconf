{ ... }:
{
  flake.nixosModules.btrbk-persist-system =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      inherit (lib)
        hasInfix
        mkEnableOption
        mkIf
        mkOption
        types
        ;

      cfg = config.preferences.btrbkPersistSystem;
      user = config.preferences.user.username;
      hostName = config.preferences.hostName;
      driveRoot = "${cfg.mountBase}/${user}/${cfg.externalDriveLabel}";
      targetParent = "${cfg.mountBase}/${user}/${cfg.externalDriveLabel}/BTRFS-BACKUPS";
      configPath = "/etc/btrbk/persist-system.conf";
      stateDir = "/var/lib/btrbk";
      codePath = "${stateDir}/persist-system-target-code";
      transactionsPath = "${stateDir}/persist-system.transactions";
      runPersistSystem = pkgs.writeShellScriptBin "btrbk-persist-system" ''
        set -eu

        code_path=${lib.escapeShellArg codePath}
        drive_root=${lib.escapeShellArg driveRoot}
        target_parent=${lib.escapeShellArg targetParent}
        host_name=${lib.escapeShellArg hostName}
        source_subvolume=${lib.escapeShellArg cfg.sourceSubvolume}
        export PATH=${
          lib.makeBinPath [
            pkgs.btrfs-progs
            pkgs.coreutils
            pkgs.util-linux
          ]
        }:$PATH
        assume_yes=0
        btrbk_args=()

        while [ "$#" -gt 0 ]; do
          case "$1" in
            -y|--yes)
              assume_yes=1
              shift
              ;;
            --)
              shift
              while [ "$#" -gt 0 ]; do
                btrbk_args+=("$1")
                shift
              done
              ;;
            *)
              btrbk_args+=("$1")
              shift
              ;;
          esac
        done

        if [ "$(id -u)" -ne 0 ]; then
          echo "btrbk-persist-system must run as root; use sudo." >&2
          exit 1
        fi
        if [ ! -e "$source_subvolume" ]; then
          echo "Source subvolume does not exist: $source_subvolume" >&2
          exit 1
        fi
        if ! ${pkgs.btrfs-progs}/bin/btrfs subvolume show "$source_subvolume" >/dev/null 2>&1; then
          echo "Source is not a Btrfs subvolume: $source_subvolume" >&2
          exit 1
        fi
        if [ ! -s "$code_path" ]; then
          echo "Missing $code_path; activate the NixOS configuration once before running backups." >&2
          exit 1
        fi

        code="$(${pkgs.coreutils}/bin/cat "$code_path")"
        case "$code" in
          [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;;
          *) echo "Invalid btrbk target code in $code_path: $code" >&2; exit 1 ;;
        esac

        target="$target_parent/$host_name-$code"
        if [ ! -d "$drive_root" ]; then
          echo "Backup drive mount path does not exist: $drive_root" >&2
          exit 1
        fi
        if ! ${pkgs.util-linux}/bin/findmnt --mountpoint "$drive_root" >/dev/null; then
          echo "Backup drive is not mounted at expected mount point: $drive_root" >&2
          exit 1
        fi
        drive_fstype="$(${pkgs.util-linux}/bin/findmnt --noheadings --output FSTYPE --mountpoint "$drive_root" | ${pkgs.coreutils}/bin/head -n 1)"
        if [ "$drive_fstype" != "btrfs" ]; then
          echo "Backup drive must be Btrfs for btrbk send/receive; $drive_root is $drive_fstype." >&2
          exit 1
        fi
        case "$target_parent" in
          "$drive_root"/*) ;;
          *) echo "Refusing unsafe target outside backup drive: $target_parent" >&2; exit 1 ;;
        esac

        if [ -e "$target_parent" ] && [ ! -d "$target_parent" ]; then
          echo "Backup root exists but is not a directory: $target_parent" >&2
          exit 1
        fi
        if [ ! -d "$target_parent" ]; then
          echo "About to create btrbk backup root on Btrfs drive:"
          echo "  drive:  $drive_root"
          echo "  root:   $target_parent"
          echo "  target: $target"
          if [ "$assume_yes" -ne 1 ]; then
            if [ ! -t 0 ]; then
              echo "Refusing to create backup root without a TTY; rerun with --yes if this is intentional." >&2
              exit 1
            fi
            printf 'Create this directory and continue? Type YES: '
            read -r answer
            if [ "$answer" != "YES" ]; then
              echo "Aborted; no directories created." >&2
              exit 1
            fi
          fi
          ${pkgs.coreutils}/bin/install -d -m 0750 -o root -g root "$target_parent"
        fi

        target_mount="$(${pkgs.util-linux}/bin/findmnt --noheadings --output TARGET -T "$target_parent" | ${pkgs.coreutils}/bin/head -n 1)"
        if [ "$target_mount" != "$drive_root" ]; then
          echo "Backup root is not on expected drive mount: $target_parent" >&2
          exit 1
        fi

        ${pkgs.coreutils}/bin/install -d -m 0750 -o root -g root "$target"
        exec ${pkgs.btrbk}/bin/btrbk -c ${lib.escapeShellArg configPath} run "''${btrbk_args[@]}"
      '';
    in
    {
      options.preferences.btrbkPersistSystem = {
        enable = mkEnableOption "manual btrbk backups for the /persist/system subvolume";

        externalDriveLabel = mkOption {
          type = types.str;
          default = "EXTERNAL DATA DRIVE";
          description = "Filesystem label below the user's removable-media mount root used for btrbk targets.";
        };

        mountBase = mkOption {
          type = types.str;
          default = "/run/media";
          description = "Base directory for user-mounted removable media.";
        };

        sourceSubvolume = mkOption {
          type = types.str;
          default = "/persist/system";
          description = "Btrfs subvolume backed up by the manual btrbk configuration.";
        };

        snapshotDir = mkOption {
          type = types.str;
          default = "/persist/.btrbk-snapshots";
          description = "Local snapshot directory on the source Btrfs filesystem; btrbk requires this directory to exist.";
        };

        targetPreserveMin = mkOption {
          type = types.str;
          default = "60d";
          description = "Minimum age window during which every target backup is preserved.";
        };
      };

      config = mkIf cfg.enable {
        assertions = [
          {
            assertion =
              !(hasInfix "\n" cfg.externalDriveLabel)
              && !(hasInfix "#" cfg.externalDriveLabel)
              && !(hasInfix "\"" cfg.externalDriveLabel);
            message = "preferences.btrbkPersistSystem.externalDriveLabel must not contain newlines, #, or double quotes because btrbk.conf has no escape syntax for quoted path values.";
          }
          {
            assertion = !(hasInfix "\n" hostName) && !(hasInfix "/" hostName) && !(hasInfix " " hostName);
            message = "preferences.hostName must be a single path-safe segment for btrbk backup target IDs.";
          }
        ];

        environment.systemPackages = [
          pkgs.btrbk
          pkgs.btrfs-progs
          runPersistSystem
        ];

        # /var/lib/btrbk holds only the generated host target suffix and transaction log; persisting it keeps the first-rebuild random target ID stable on impermanent roots.
        impermanence.nixos.directories = [ stateDir ];

        system.activationScripts.btrbk-persist-system-config = {
          deps = [
            "etc"
            "users"
            # Persist /var/lib/btrbk before reading/writing the host target code so an
            # impermanent root does not regenerate a throwaway ID and leave umask 077
            # for later activation scripts (usrbinenv creates /usr as 0700 under that).
            "createPersistentStorageDirs"
          ];
          text = ''
                        set -eu

                        state_dir=${lib.escapeShellArg stateDir}
                        code_path=${lib.escapeShellArg codePath}
                        snapshot_dir=${lib.escapeShellArg cfg.snapshotDir}
                        config_path=${lib.escapeShellArg configPath}
                        target_parent=${lib.escapeShellArg targetParent}
                        host_name=${lib.escapeShellArg hostName}

                        ${pkgs.coreutils}/bin/install -d -m 0750 -o root -g root "$state_dir"
                        if [ ! -s "$code_path" ]; then
                          # Subshell keeps the activation umask at 0022; a leaked 077 made
                          # later mkdir -p /usr/bin create root-only /usr and broke #!/usr/bin/env.
                          (
                            umask 077
                            ${pkgs.openssl}/bin/openssl rand -hex 4 > "$code_path.tmp"
                            mv "$code_path.tmp" "$code_path"
                          )
                        fi

                        code="$(${pkgs.coreutils}/bin/cat "$code_path")"
                        case "$code" in
                          [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;;
                          *) echo "Invalid btrbk target code in $code_path: $code" >&2; exit 1 ;;
                        esac

                        ${pkgs.coreutils}/bin/install -d -m 0750 -o root -g root "$snapshot_dir"
                        ${pkgs.coreutils}/bin/install -d -m 0755 -o root -g root "$(${pkgs.coreutils}/bin/dirname "$config_path")"

                        cat > "$config_path" <<EOF_BTRBK
            # Generated by modules/nixos/terminal/btrbk.nix.
            # Manual run: sudo btrbk -c ${configPath} run
            timestamp_format        long-iso
            snapshot_create         ondemand
            snapshot_preserve_min   latest
            snapshot_preserve       no
            target_preserve_min     ${cfg.targetPreserveMin}
            target_preserve         no
            incremental             yes
            transaction_log         ${transactionsPath}
            lockfile                /run/btrbk-persist-system.lock

            snapshot_dir            "${cfg.snapshotDir}"

            subvolume               "${cfg.sourceSubvolume}"
              snapshot_name         backup
              target                "$target_parent/$host_name-$code"
            EOF_BTRBK
                        chmod 0644 "$config_path"
          '';
        };

        systemd.services.btrbk-persist-system = {
          description = "Manual btrbk backup for /persist/system";
          unitConfig.Documentation = [
            "man:btrbk(1)"
            "https://digint.ch/btrbk/doc/readme.html"
          ];
          path = [ pkgs.btrfs-progs ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${runPersistSystem}/bin/btrbk-persist-system";
            Nice = 10;
            IOSchedulingClass = "best-effort";
          };
        };
      };
    };
}
