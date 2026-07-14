{ inputs, ... }:
let
  # Stable is the default package universe. Edge AI/web gateway and fast-moving
  # GUI packages are routed through nixpkgs-unstable here so their package
  # files can stay normal callPackage derivations without ambient
  # `{ unstable, ... }` parameters.
  edgePackages = [
    "acp-chat"
    "cliproxyapi"
    # Limux's GTK Rust bindings require rustc >= 1.92; keep it on unstable
    # until the stable channel's Rust toolchain catches up.
    "omniroute"
    "openchamber-web"
    "limux"
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
        name: if builtins.elem name edgePackages then unstablePkgs.callPackage else stablePkgs.callPackage;

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
    (builtins.foldl' (acc: filename: acc // (toPackage filename)) { } files)
    // {
      # Re-export the locked llm-agents Paseo desktop package so terminal
      # profiles install it with the rest of this flake's system packages.
      # Source: github:numtide/llm-agents.nix packages.<system>.paseo-desktop.
      paseo = inputs.llm-agents.packages.${stablePkgs.stdenv.hostPlatform.system}.paseo-desktop;
      grok = inputs.llm-agents.packages.${stablePkgs.stdenv.hostPlatform.system}.grok;
    };
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
