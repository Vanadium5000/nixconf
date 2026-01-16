{ ... }:
{
  # Generates a shell script to manage a persistent file symlinked from Shared/Data.
  #
  # Args:
  #   user: The username (string).
  #   fileName: The name of the file in Shared/Data (e.g., "permissions.sqlite").
  #   targetFile: The absolute path where the file should be linked (e.g., "/home/${user}/.librewolf/${user}.default/permissions.sqlite").
  #   sourceFile: (Optional) Path to a source file to initialize from if the persistent file doesn't exist.
  #
  # Returns:
  #   A string containing the shell script logic.
  mkPersistentFileScript =
    {
      user,
      fileName,
      targetFile,
      sourceFile ? null,
      defaultContent ? "",
    }:
    ''
      USER_HOME="/home/${user}"
      SHARED_DATA_DIR="$USER_HOME/Shared/Data"
      PERSISTENT_FILE="$SHARED_DATA_DIR/${fileName}"
      TARGET_FILE="${targetFile}"

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
              echo '${defaultContent}' > "$PERSISTENT_FILE"
            ''
        }
        chown ${user}:users "$PERSISTENT_FILE"
        chmod 644 "$PERSISTENT_FILE"
      fi

      # Ensure target directory exists
      TARGET_DIR="$(dirname "$TARGET_FILE")"
      mkdir -p "$TARGET_DIR"
      chown ${user}:users "$TARGET_DIR"

      # Create symlink
      if [ -L "$TARGET_FILE" ]; then
        # Check if it points to the right place? For now, assume if it's a link, we might re-link or leave it.
        # The original script removed it if it was a link, then re-linked.
        rm "$TARGET_FILE"
      elif [ -f "$TARGET_FILE" ]; then
        # If it's a regular file (not a symlink), we back it up just in case
        mv "$TARGET_FILE" "$TARGET_FILE.bak"
      fi

      # Only create the link if the persistent file exists OR if we are okay with broken links?
      ln -sf "$PERSISTENT_FILE" "$TARGET_FILE"
      chown -h ${user}:users "$TARGET_FILE"
    '';
}
