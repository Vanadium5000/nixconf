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
    builtins.replaceStrings [ "-" "/" ] [ "\\x2d" "-" ] stripped;
in
{
  # Creates a user-path bind mount configuration.
  #
  # Arguments:
  #   pkgs: Package set supplying activation and systemd service tools.
  #   user: The username (string)
  #   fileName: Shared/Data state source name (e.g., "permissions.sqlite")
  #   targetFile: The absolute path where the file should appear
  #   sourcePath: Explicit bind source; mutually exclusive with fileName.
  #   isDirectory: Whether the source and target are directories.
  #
  # Returns a bind mount fileSystems entry and the service that prepares it.
  # The caller must include systemdService and fileSystems in its module.
  #
  mkUserPath =
    {
      pkgs,
      user,
      targetFile,
      fileName ? null,
      sourcePath ? null,
      isDirectory ? false,
    }:
    let
      sharedDataDir = "/home/${user}/Shared/Data";
      bindSource =
        if sourcePath != null && fileName != null then
          throw "mkUserPath: specify exactly one of sourcePath or fileName"
        else if sourcePath != null then
          sourcePath
        else if fileName != null then
          "${sharedDataDir}/${fileName}"
        else
          throw "mkUserPath: missing sourcePath or fileName";
      sourceDirectory = dirOf bindSource;
      sharedDataSource = fileName != null;
      sourceDescription = if sharedDataSource then "Shared/Data state" else "declarative configuration";

      # Shared/Data sources are writable state and may be initialized from an
      # existing target. Explicit sources are declarative files and must exist
      # before the mount hides the legacy target.
      setupScript = ''
        SOURCE_DIRECTORY="${sourceDirectory}"
        SOURCE_PATH="${bindSource}"
        TARGET_FILE="${targetFile}"

        ${lib.optionalString sharedDataSource ''
          mkdir -p "$SOURCE_DIRECTORY"
          chown ${user}:users "$SOURCE_DIRECTORY"
        ''}

        # Refuse source indirection: the mount must expose the declared path.
        if [ -L "$SOURCE_PATH" ]; then
          echo "ERROR: ${sourceDescription} bind source '$SOURCE_PATH' is a symlink." >&2
          exit 1
        fi

        ${
          if isDirectory then
            if sharedDataSource then
              ''
                # Migrate a first-run directory before creating the state source.
                if [ -e "$SOURCE_PATH" ] && [ ! -d "$SOURCE_PATH" ]; then
                  echo "ERROR: Bind source '$SOURCE_PATH' is not a directory." >&2
                  exit 1
                fi

                if [ ! -e "$SOURCE_PATH" ] && [ -d "$TARGET_FILE" ] && ! mountpoint -q "$TARGET_FILE"; then
                  if [ -L "$TARGET_FILE" ]; then
                    mkdir -p "$SOURCE_PATH"
                    cp -aL "$TARGET_FILE"/. "$SOURCE_PATH"/
                  else
                    mv "$TARGET_FILE" "$SOURCE_PATH"
                  fi
                elif [ ! -e "$SOURCE_PATH" ]; then
                  mkdir -p "$SOURCE_PATH"
                fi
                chown ${user}:users "$SOURCE_PATH"
                chmod 755 "$SOURCE_PATH"
              ''
            else
              ''
                if [ ! -d "$SOURCE_PATH" ]; then
                  echo "ERROR: Bind source '$SOURCE_PATH' is not a directory." >&2
                  exit 1
                fi
              ''
          else if sharedDataSource then
            ''
              if [ -d "$SOURCE_PATH" ]; then
                echo "ERROR: Bind source '$SOURCE_PATH' is a directory (expected file)." >&2
                exit 1
              fi

              if [ ! -f "$SOURCE_PATH" ]; then
                # Existing user data wins over a new empty state file.
                if [ -f "$TARGET_FILE" ] && [ -s "$TARGET_FILE" ]; then
                  cp "$TARGET_FILE" "$SOURCE_PATH"
                else
                  touch "$SOURCE_PATH"
                fi
                chown ${user}:users "$SOURCE_PATH"
                chmod 644 "$SOURCE_PATH"
              fi
            ''
          else
            ''
              if [ ! -f "$SOURCE_PATH" ]; then
                echo "ERROR: Bind source '$SOURCE_PATH' is not a regular file." >&2
                exit 1
              fi
            ''
        }

        # Ensure target directory exists
        TARGET_DIR="$(dirname "$TARGET_FILE")"
        mkdir -p "$TARGET_DIR"
        chown ${user}:users "$TARGET_DIR"
      '';

      # Bind mount setup script (ensure target file exists for mount point)
      bindSetupScript = ''
        ${setupScript}

        # A live bind already presents the source at its target. Setup only
        # prepares an unmounted mount point and never moves live state.
        if ! mountpoint -q "$TARGET_FILE"; then
          ${
            if isDirectory then
              ''
                if [ -L "$TARGET_FILE" ]; then
                  if [ -d "$TARGET_FILE" ]; then
                    if ! diff -qr "$SOURCE_PATH" "$TARGET_FILE" >/dev/null; then
                      backup="$TARGET_FILE.symlink.pre-nixos-bind.$(date +%Y%m%d%H%M%S)"
                      mkdir -p "$backup"
                      cp -aL "$TARGET_FILE"/. "$backup"/
                    fi
                    rm "$TARGET_FILE"
                  else
                    mv "$TARGET_FILE" "$TARGET_FILE.symlink.pre-nixos-bind.$(date +%Y%m%d%H%M%S)"
                  fi
                elif [ -d "$TARGET_FILE" ]; then
                  mv "$TARGET_FILE" "$TARGET_FILE.pre-nixos-bind.$(date +%Y%m%d%H%M%S)"
                elif [ -e "$TARGET_FILE" ]; then
                  mv "$TARGET_FILE" "$TARGET_FILE.pre-nixos-bind.$(date +%Y%m%d%H%M%S)"
                fi

                mkdir -p "$TARGET_FILE"
                chown ${user}:users "$TARGET_FILE"
              ''
            else
              ''
                if [ -L "$TARGET_FILE" ]; then
                  if [ -f "$TARGET_FILE" ] && ! cmp -s "$TARGET_FILE" "$SOURCE_PATH"; then
                    cp -L "$TARGET_FILE" "$TARGET_FILE.pre-nixos-bind.$(date +%Y%m%d%H%M%S)"
                    rm "$TARGET_FILE"
                  elif [ -f "$TARGET_FILE" ]; then
                    rm "$TARGET_FILE"
                  else
                    mv "$TARGET_FILE" "$TARGET_FILE.symlink.pre-nixos-bind.$(date +%Y%m%d%H%M%S)"
                  fi
                elif [ -d "$TARGET_FILE" ]; then
                  mv "$TARGET_FILE" "$TARGET_FILE.dir.pre-nixos-bind.$(date +%Y%m%d%H%M%S)"
                elif [ -e "$TARGET_FILE" ] && ! cmp -s "$TARGET_FILE" "$SOURCE_PATH"; then
                  mv "$TARGET_FILE" "$TARGET_FILE.pre-nixos-bind.$(date +%Y%m%d%H%M%S)"
                fi

                if [ ! -e "$TARGET_FILE" ]; then
                  touch "$TARGET_FILE"
                fi
                chown ${user}:users "$TARGET_FILE"
              ''
          }
        fi
      '';

      # Systemd mount unit name (for dependencies)
      systemdUnit = "${escapeSystemdPath targetFile}.mount";
      systemdService = {
        description = "Prepare ${targetFile} bind mount";
        before = [ systemdUnit ];
        requiredBy = [ systemdUnit ];
        path = [
          pkgs.coreutils
          pkgs.diffutils
          pkgs.util-linux
        ];
        script = bindSetupScript;
        unitConfig = {
          DefaultDependencies = false;
          RequiresMountsFor = [
            sourceDirectory
            (dirOf targetFile)
          ];
        };
        serviceConfig.Type = "oneshot";
      };

    in
    {
      fileSystems = {
        "${targetFile}" = {
          device = bindSource;
          fsType = "none";
          options = [
            "bind"
            "nofail"
          ];
        };
      };

      inherit systemdService systemdUnit;
    };
}
