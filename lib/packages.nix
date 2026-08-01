{ lib }:
let
  directoryNamesWithPackage =
    root:
    let
      entries = builtins.readDir root;
      dirs = builtins.filter (name: entries.${name} == "directory") (builtins.attrNames entries);
    in
    builtins.filter (name: builtins.pathExists (root + "/${name}/package.nix")) dirs;

  cleanSourceWithoutBuildOutputs =
    src:
    lib.cleanSourceWith {
      inherit src;
      filter =
        path: _type:
        !(builtins.elem (baseNameOf path) [
          "node_modules"
          ".bun"
          "dist"
          "coverage"
        ]);
    };
in
{
  inherit directoryNamesWithPackage cleanSourceWithoutBuildOutputs;

  callDirectoryPackages =
    {
      root,
      pkgs,
      edgePackages ? [ ],
      edgePkgs ? pkgs.unstable or pkgs,
      excludeNames ? [ ],
      packageArgs ? (_name: { }),
    }:
    builtins.foldl' (
      acc: name:
      let
        callPackage = if builtins.elem name edgePackages then edgePkgs.callPackage else pkgs.callPackage;
      in
      acc // { "${name}" = callPackage (root + "/${name}/package.nix") (packageArgs name); }
    ) { } (lib.subtractLists excludeNames (directoryNamesWithPackage root));

  warnOnMissingCoverage =
    {
      packageNames,
      coveredNames,
      context,
    }:
    let
      missing = lib.subtractLists coveredNames packageNames;
    in
    if missing == [ ] then
      ""
    else
      lib.warn "${context}: update-pkgs has no workflow coverage for ${builtins.concatStringsSep ", " missing}" "";

  warnOnUnexpectedRootEntries =
    { roots }:
    let
      checks = lib.mapAttrsToList (
        name: rule:
        let
          entries = builtins.readDir (../. + "/${name}");
          unexpected = lib.filter (
            entry: !(builtins.elem entry rule.allowed) && entries.${entry} != rule.expectedType
          ) (builtins.attrNames entries);
        in
        if unexpected == [ ] then
          ""
        else
          lib.warn "${name}: root entries must be ${rule.expectedType}s; found ${builtins.concatStringsSep ", " unexpected}" ""
      ) roots;
    in
    builtins.concatStringsSep "" checks;

  warnOnPackageDirectoryContract =
    { roots }:
    let
      checkRoot =
        rootName: rule:
        let
          root = ../. + "/${rootName}";
          entries = builtins.readDir root;
          requiredFiles = rule.requiredFiles or [ rule.requiredFile ];
          allowNamedDefinition = rule.allowNamedDefinition or false;
          allowedDirectories = rule.allowedDirectories or [ ];
          requiredContract = requiredFiles ++ lib.optional allowNamedDefinition "<directory-name>.nix";
          invalid = lib.filter (
            entry:
            let
              entryPath = root + "/${entry}";
              hasRequiredFile = lib.any (file: builtins.pathExists (entryPath + "/${file}")) requiredFiles;
              hasNamedDefinition = allowNamedDefinition && builtins.pathExists (entryPath + "/${entry}.nix");
              isAllowedDirectory =
                entries.${entry} == "directory"
                && (builtins.elem entry allowedDirectories || hasRequiredFile || hasNamedDefinition);
            in
            !isAllowedDirectory
          ) (builtins.attrNames entries);
        in
        if invalid == [ ] then
          ""
        else
          lib.warn "${rootName}: every first-level entry must be a directory containing one of ${builtins.concatStringsSep ", " requiredContract}${lib.optionalString (allowedDirectories != [ ]) " or an allowed infrastructure directory: ${builtins.concatStringsSep ", " allowedDirectories}"}; invalid: ${builtins.concatStringsSep ", " invalid}" "";
    in
    builtins.concatStringsSep "" (lib.mapAttrsToList checkRoot roots);
}
