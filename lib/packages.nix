{ lib }:
let
  directoryNamesWithPackage =
    root:
    let
      entries = builtins.readDir root;
      dirs = builtins.filter (name: entries.${name} == "directory") (builtins.attrNames entries);
    in
    builtins.filter (name: builtins.pathExists (root + "/${name}/package.nix")) dirs;
in
{
  inherit directoryNamesWithPackage;

  callDirectoryPackages =
    {
      root,
      pkgs,
      edgePackages ? [ ],
      edgePkgs ? pkgs.unstable or pkgs,
      excludeNames ? [ ],
    }:
    builtins.foldl' (
      acc: name:
      let
        callPackage = if builtins.elem name edgePackages then edgePkgs.callPackage else pkgs.callPackage;
      in
      acc // { "${name}" = callPackage (root + "/${name}/package.nix") { }; }
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
      builtins.warn "${context}: update-pkgs has no workflow coverage for ${builtins.concatStringsSep ", " missing}" "";
}
