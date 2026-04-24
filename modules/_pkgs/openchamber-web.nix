{
  lib,
  buildNpmPackage,
  fetchurl,
  python3,
  pkg-config,
  nodePackages,
}:

# Keep the historical top-level package path stable while the real package
# inputs live in ./openchamber/ alongside their vendored lockfile.
import ./openchamber/openchamber-web.nix {
  inherit
    lib
    buildNpmPackage
    fetchurl
    python3
    pkg-config
    nodePackages
    ;
}
