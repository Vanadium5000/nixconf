{ lib, ... }:
let

  # Escape a path for use as a systemd mount unit name.
  # Systemd mount units are named after the mount point with / replaced by -.
  escapeSystemdPath =
    path:
    let
      # Remove leading slash for the unit name
      stripped = lib.removePrefix "/" path;
    in
    builtins.replaceStrings [ "/" ] [ "-" ] stripped;
in
rec {
  # Creates a persistent file configuration using either symlinks or bind mounts.
  #
  # Arguments:
  #   method: "symlink" or "bind" - the persistence mechanism to use
  #     - "symlink": Creates a symlink from targetFile to the persistent location.
  #                  Simple but can be overwritten by applications that replace symlinks.
  #     - "bind": Uses systemd bind mounts. More robust as applications see a regular file,
  #               but requires proper systemd service ordering.
  #
  #   user: The username (string)
  #   fileName: The name of the file in Shared/Data (e.g., "permissions.sqlite")
  #   targetFile: The absolute path where the file should appear
  #   sourceFile: (Optional) Path to initialize from if persistent file doesn't exist
  #   defaultContent: (Optional) Default content if creating a new file
  #
  # Returns:
  #   For method = "symlink":
  #     A string containing the shell script (for use in activationScripts)
  #
  #   For method = "bind":
  #     An attrset with:
  #       - activationScript: Shell script to ensure files/dirs exist with correct ownership
  #       - fileSystems: NixOS fileSystems attrset for the bind mount
  #       - systemdUnit: The name of the mount unit (for service dependencies)
  #
  mkPersistent =
    {
      method ? "symlink",
      user,
      fileName,
      targetFile,
      sourceFile ? null,
      defaultContent ? "",
      isDirectory ? false,
    }:
    let
      sharedDataDir = "/home/${user}/Shared/Data";
      persistentFile = "${sharedDataDir}/${fileName}";

      # Common setup script for ensuring directories and files exist
      setupScript = ''
        USER_HOME="/home/${user}"
        SHARED_DATA_DIR="${sharedDataDir}"
        PERSISTENT_FILE="${persistentFile}"
        TARGET_FILE="${targetFile}"

        # Ensure shared data directory exists
        mkdir -p "$SHARED_DATA_DIR"
        chown ${user}:users "$SHARED_DATA_DIR"

        # Security: refuse to use a symlink as the persistent file (prevents symlink attacks)
        if [ -L "$PERSISTENT_FILE" ]; then
          echo "ERROR: Persistent file '$PERSISTENT_FILE' is a symlink. Refusing to use." >&2
          exit 1
        fi

        ${
          if isDirectory then
            ''
              # Directory initialization
              if [ -f "$PERSISTENT_FILE" ]; then
                 echo "ERROR: Persistent path '$PERSISTENT_FILE' exists and is a file (expected directory)." >&2
                 exit 1
              fi

              if [ ! -d "$PERSISTENT_FILE" ]; then
                mkdir -p "$PERSISTENT_FILE"
                chown ${user}:users "$PERSISTENT_FILE"
                chmod 755 "$PERSISTENT_FILE"
              fi
            ''
          else
            ''
              # File initialization
              if [ -d "$PERSISTENT_FILE" ]; then
                 echo "ERROR: Persistent path '$PERSISTENT_FILE' exists and is a directory (expected file)." >&2
                 exit 1
              fi

              if [ ! -f "$PERSISTENT_FILE" ]; then
                ${
                  if sourceFile != null then
                    ''
                      cp "${sourceFile}" "$PERSISTENT_FILE"
                    ''
                  else
                    ''
                      # Initialize from target if it exists and has content, otherwise use defaultContent
                      if [ -f "$TARGET_FILE" ] && [ -s "$TARGET_FILE" ]; then
                        cp "$TARGET_FILE" "$PERSISTENT_FILE"
                      elif [ -n '${defaultContent}' ]; then
                        printf '%s' '${defaultContent}' > "$PERSISTENT_FILE"
                      else
                        # No source, no default - create empty as last resort
                        touch "$PERSISTENT_FILE"
                      fi
                    ''
                }
                chown ${user}:users "$PERSISTENT_FILE"
                chmod 644 "$PERSISTENT_FILE"
              fi
            ''
        }

        # Ensure target directory exists
        TARGET_DIR="$(dirname "$TARGET_FILE")"
        mkdir -p "$TARGET_DIR"
        chown ${user}:users "$TARGET_DIR"
      '';

      # Symlink-specific script portion
      symlinkScript = ''
        ${setupScript}

        # Handle existing target: symlink, regular file, or directory
        if [ -L "$TARGET_FILE" ]; then
          # Remove existing symlink (including broken ones)
          rm "$TARGET_FILE"
        elif [ -d "$TARGET_FILE" ]; then
          # Back up directories (unusual but possible)
          mv "$TARGET_FILE" "$TARGET_FILE.dir.bak.$(date +%Y%m%d%H%M%S)"
        elif [ -e "$TARGET_FILE" ]; then
          # Back up regular files or other types (might contain user data)
          mv "$TARGET_FILE" "$TARGET_FILE.bak.$(date +%Y%m%d%H%M%S)"
        fi

        # Create symlink
        ln -sf "$PERSISTENT_FILE" "$TARGET_FILE"
        chown -h ${user}:users "$TARGET_FILE"
      '';

      # Bind mount setup script (ensure target file exists for mount point)
      bindSetupScript = ''
        ${setupScript}

        ${
          if isDirectory then
            ''
              # Directory bind mount target setup
              if [ -L "$TARGET_FILE" ]; then
                 rm "$TARGET_FILE"
              elif [ -f "$TARGET_FILE" ]; then
                 mv "$TARGET_FILE" "$TARGET_FILE.bak.$(date +%Y%m%d%H%M%S)"
              fi

              if [ ! -d "$TARGET_FILE" ]; then
                 mkdir -p "$TARGET_FILE"
                 chown ${user}:users "$TARGET_FILE"
              fi
            ''
          else
            ''
              # For bind mounts, we need the target file to exist as a mount point.
              # Handle edge cases: symlinks, directories, or other file types.
              if [ -L "$TARGET_FILE" ]; then
                # Remove symlinks (including broken ones) - bind mounts need a real file
                rm "$TARGET_FILE"
                touch "$TARGET_FILE"
                chown ${user}:users "$TARGET_FILE"
              elif [ -d "$TARGET_FILE" ]; then
                # Cannot bind-mount a file over a directory
                mv "$TARGET_FILE" "$TARGET_FILE.dir.bak.$(date +%Y%m%d%H%M%S)"
                touch "$TARGET_FILE"
                chown ${user}:users "$TARGET_FILE"
              elif [ ! -e "$TARGET_FILE" ]; then
                # Target doesn't exist, create empty file as mount point
                touch "$TARGET_FILE"
                chown ${user}:users "$TARGET_FILE"
              fi
              # If it's already a regular file, leave it (will be shadowed by bind mount)
            ''
        }
      '';

      # Systemd mount unit name (for dependencies)
      systemdUnit = "${escapeSystemdPath targetFile}.mount";

    in
    if method == "symlink" then
      symlinkScript
    else if method == "bind" then
      {
        activationScript = bindSetupScript;

        fileSystems = {
          "${targetFile}" = {
            device = persistentFile;
            fsType = "none";
            options = [
              "bind"
              "nofail"
              "x-systemd.requires=local-fs.target"
            ];
          };
        };

        inherit systemdUnit;
      }
    else
      throw "mkPersistent: invalid method '${method}', expected 'symlink' or 'bind'";

  # Convenience alias for backward compatibility
  mkPersistentFileScript =
    args:
    mkPersistent (
      args
      // {
        method = "symlink";
      }
    );
}
