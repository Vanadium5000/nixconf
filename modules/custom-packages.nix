{ ... }:
let
  getPackages =
    callPackage:
    let
      # All .nix files and directories in ./_pkgs/ except default.nix
      files = builtins.attrNames (builtins.removeAttrs (builtins.readDir ./_pkgs) [ "default.nix" ]);

      # Turn filename.nix → name = callPackage ./filename.nix {};
      toPackage = name: {
        "${builtins.replaceStrings [ ".nix" ] [ "" ] name}" = callPackage (./_pkgs + "/${name}") { };
      };

    in
    builtins.foldl' (acc: filename: acc // (toPackage filename)) { } files;
in
{
  flake.overlays.customPackages = final: prev: getPackages final.callPackage;

  perSystem =
    { pkgs, ... }:
    {
      packages = getPackages pkgs.callPackage;
    };
}
