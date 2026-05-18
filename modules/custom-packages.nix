{ ... }:
let
  # Stable is the default package universe. Edge AI/web gateway packages are
  # routed through nixpkgs-unstable here so their package files can stay normal
  # callPackage derivations without ambient `{ unstable, ... }` parameters.
  edgeAiGatewayPackages = [
    "acp-chat"
    "cliproxyapi"
    "omniroute"
    "openchamber-web"
  ];

  getPackages =
    {
      stablePkgs,
      unstablePkgs ? stablePkgs.unstable,
    }:
    let
      entries = builtins.readDir ./_pkgs;

      # Only treat top-level .nix files as exported packages so support files can
      # live in nested directories without being misread as package attrs.
      files = builtins.filter (
        name:
        entries.${name} == "regular" && builtins.match ".*\\.nix" name != null && name != "default.nix"
      ) (builtins.attrNames entries);

      callPackageFor =
        name:
        if builtins.elem name edgeAiGatewayPackages then
          unstablePkgs.callPackage
        else
          stablePkgs.callPackage;

      # Turn filename.nix → name = callPackage ./filename.nix {};
      toPackage =
        filename:
        let
          name = builtins.replaceStrings [ ".nix" ] [ "" ] filename;
        in
        {
          "${name}" = (callPackageFor name) (./_pkgs + "/${filename}") { };
        };

    in
    builtins.foldl' (acc: filename: acc // (toPackage filename)) { } files;
in
{
  flake.overlays.customPackages = final: prev: {
    customPackages = getPackages {
      stablePkgs = final;
      unstablePkgs = final.unstable;
    };
  };

  perSystem =
    { pkgs, ... }:
    {
      packages = getPackages {
        stablePkgs = pkgs;
        unstablePkgs = pkgs.unstable;
      };
    };
}
