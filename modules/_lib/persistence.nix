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

        # Initialize persistent file if it doesn't exist
        if [ ! -f "$PERSISTENT_FILE" ]; then
          ${
            if sourceFile != null then
              ''
                cp "${sourceFile}" "$PERSISTENT_FILE"
              ''
            else if defaultContent == "" then
              ''
                touch "$PERSISTENT_FILE"
              ''
            else
              ''
                printf '%s' '${defaultContent}' > "$PERSISTENT_FILE"
              ''
          }
          chown ${user}:users "$PERSISTENT_FILE"
          chmod 644 "$PERSISTENT_FILE"
        fi

        # Ensure target directory exists
        TARGET_DIR="$(dirname "$TARGET_FILE")"
        mkdir -p "$TARGET_DIR"
        chown ${user}:users "$TARGET_DIR"
      '';

      # Symlink-specific script portion
      symlinkScript = ''
        ${setupScript}

        # Handle existing target file
        if [ -L "$TARGET_FILE" ]; then
          rm "$TARGET_FILE"
        elif [ -f "$TARGET_FILE" ]; then
          # Back up regular files (might contain user data)
          mv "$TARGET_FILE" "$TARGET_FILE.bak.$(date +%Y%m%d%H%M%S)"
        fi

        # Create symlink
        ln -sf "$PERSISTENT_FILE" "$TARGET_FILE"
        chown -h ${user}:users "$TARGET_FILE"
      '';

      # Bind mount setup script (ensure target file exists for mount point)
      bindSetupScript = ''
        ${setupScript}

        # For bind mounts, we need the target file to exist as a mount point
        if [ ! -f "$TARGET_FILE" ]; then
          touch "$TARGET_FILE"
          chown ${user}:users "$TARGET_FILE"
        fi
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
