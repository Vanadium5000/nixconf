{ inputs, ... }:
{
  flake.overlays.customPackages =
    final: prev:
    builtins.mapAttrs (name: value: final.callPackage value { }) (
      inputs.import-tree [
        ./_pkgs
      ]
    );
}
