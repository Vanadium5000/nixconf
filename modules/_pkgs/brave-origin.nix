{ callPackage, ... }@args:

# Keep only this shim at modules/_pkgs/*.nix so custom-packages.nix and
# update-pkgs.nix export one package while helper files live beside update.sh.
# Source: modules/custom-packages.nix top-level scan.
callPackage ./brave-origin/package.nix (removeAttrs args [ "callPackage" ])
