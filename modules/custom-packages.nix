{ inputs, ... }:
{
  flake.overlays.customPackages =
    final: prev:

    let
      inherit (final) callPackage;

      # All .nix files in ./_pkgs/ except default.nix
      files = builtins.attrNames (builtins.removeAttrs (builtins.readDir ./_pkgs) [ "default.nix" ]);

      # Turn filename.nix → name = callPackage ./filename.nix {};
      toPackage = name: {
        "${builtins.replaceStrings [ ".nix" ] [ "" ] name}" = callPackage (./_pkgs + "/${name}") { };
      };

    in
    builtins.foldl' (acc: filename: acc // (toPackage filename)) { } files;
}
