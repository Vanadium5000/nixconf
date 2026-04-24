{ ... }:
let
  getPackages =
    callPackage:
    let
      entries = builtins.readDir ./_pkgs;

      # Only treat top-level .nix files as exported packages so support files can
      # live in nested directories without being misread as package attrs.
      files = builtins.filter (
        name:
        entries.${name} == "regular" && builtins.match ".*\\.nix" name != null && name != "default.nix"
      ) (builtins.attrNames entries);

      # Turn filename.nix → name = callPackage ./filename.nix {};
      toPackage = name: {
        "${builtins.replaceStrings [ ".nix" ] [ "" ] name}" = callPackage (./_pkgs + "/${name}") { };
      };

    in
    builtins.foldl' (acc: filename: acc // (toPackage filename)) { } files;
in
{
  flake.overlays.customPackages = final: prev: { customPackages = getPackages final.callPackage; };

  perSystem =
    { pkgs, ... }:
    {
      packages = getPackages pkgs.callPackage;
    };
}
