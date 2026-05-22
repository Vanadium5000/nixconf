{
  lib,
  root ? ../..,
}:
let
  inherit (lib)
    concatMapStringsSep
    escapeShellArg
    optionalAttrs
    ;

  sourceNames = {
    checkout = "checkout";
    store = "store";
  };

  assertRelative =
    relativePath:
    if builtins.match "/.*" relativePath != null then
      throw "configFiles: relativePath must be relative, got '${relativePath}'"
    else
      relativePath;
in
rec {
  inherit sourceNames;

  mkFile =
    { relativePath, storePath }:
    {
      relativePath = assertRelative relativePath;
      storePath = builtins.path {
        path = storePath;
        name = builtins.baseNameOf (toString storePath);
      };
    };

  known = rec {
    ohMyPoshTheme = mkFile {
      relativePath = "modules/programmes/oh-my-posh/settings.json";
      storePath = root + "/modules/programmes/oh-my-posh/settings.json";
    };

    vscodiumSettings = mkFile {
      relativePath = "modules/nixos/desktop/vscodium/settings.json";
      storePath = root + "/modules/nixos/desktop/vscodium/settings.json";
    };

    opencodeStateDirectory = mkFile {
      relativePath = "modules/nixos/terminal/opencode";
      storePath = root + "/modules/nixos/terminal/opencode";
    };

    opencodeModels = mkFile {
      relativePath = "${opencodeStateDirectory.relativePath}/models.json";
      storePath = root + "/modules/nixos/terminal/opencode/models.json";
    };

    opencodeState = mkFile {
      relativePath = "${opencodeStateDirectory.relativePath}/state.json";
      storePath = root + "/modules/nixos/terminal/opencode/state.json";
    };

    opencodePresets = mkFile {
      relativePath = "${opencodeStateDirectory.relativePath}/presets.json";
      storePath = root + "/modules/nixos/terminal/opencode/presets.json";
    };

    opencodeLocalPatches = mkFile {
      relativePath = "${opencodeStateDirectory.relativePath}/_model-local-patches.json";
      storePath = root + "/modules/nixos/terminal/opencode/_model-local-patches.json";
    };
  };

  managedFiles = with known; [
    ohMyPoshTheme
    vscodiumSettings
    opencodeModels
    opencodeState
    opencodePresets
    opencodeLocalPatches
  ];

  withInputPaths = files: map (file: file // { inputPath = file.storePath; }) files;

  mkStoreRoot =
    {
      pkgs,
      files ? managedFiles,
    }:
    let
      filesWithInputs = withInputPaths files;
    in
    pkgs.runCommand "nixconf-config-files"
      { configFileInputs = map (file: file.inputPath) filesWithInputs; }
      ''
        mkdir -p "$out"
        ${concatMapStringsSep "\n" (file: ''
          target="$out/${file.relativePath}"
          source=${escapeShellArg file.inputPath}
          mkdir -p "$(dirname "$target")"
          if [ -d "$source" ]; then
            mkdir -p "$target"
            cp -R "$source"/. "$target"/
          else
            cp "$source" "$target"
          fi
        '') filesWithInputs}
      '';

  mkSourceDirectory =
    {
      source,
      checkoutDirectory,
      storeDirectory,
    }:
    if source == sourceNames.checkout then checkoutDirectory else toString storeDirectory;

  mkConfigSourceDirectory =
    { config, storeDirectory }:
    mkSourceDirectory {
      source = config.preferences.configFiles.source;
      checkoutDirectory = config.preferences.paths.configDirectory;
      inherit storeDirectory;
    };

  mkSourcePath =
    {
      source,
      checkoutDirectory,
      relativePath,
      storePath,
    }:
    if source == sourceNames.checkout then
      "${checkoutDirectory}/${assertRelative relativePath}"
    else
      toString storePath;

  mkConfigSourcePath =
    {
      config,
      relativePath,
      storePath,
    }:
    mkSourcePath {
      source = config.preferences.configFiles.source;
      checkoutDirectory = config.preferences.paths.configDirectory;
      inherit relativePath storePath;
    };

  mkUserFile =
    {
      config,
      relativePath,
      storePath,
      file ? { },
    }:
    file
    // {
      source = mkConfigSourcePath {
        inherit config relativePath storePath;
      };
    }
    // optionalAttrs (config.preferences.configFiles.source == sourceNames.store && !(file ? type)) {
      # Store-backed managed config should land as a normal mutable file, while
      # checkout-backed config remains a symlink for live editing from ~/nixconf.
      type = "copy";
    };
}
