{ inputs, self, ... }:
let
  workflow = import ../../external-packages/update-pkgs/workflow.nix;
  edgePackages = workflow.edgePackages;
  modulePackageNames = [
    "bunjs-scripts"
    "qs-menus"
  ];
  customPackageNames = self.lib.packages.directoryNamesWithPackage ../.;
  externalPackageNames = self.lib.packages.directoryNamesWithPackage ../../external-packages;
  coverageCheck = self.lib.packages.warnOnMissingCoverage {
    packageNames = externalPackageNames;
    coveredNames = builtins.attrNames workflow.updateModes;
    context = "external-packages";
  };

  getPackages =
    {
      stablePkgs,
      unstablePkgs ? stablePkgs.unstable,
    }:
    let
      custom = self.lib.packages.callDirectoryPackages {
        root = ../.;
        pkgs = stablePkgs;
        excludeNames = modulePackageNames;
      };
      external = self.lib.packages.callDirectoryPackages {
        root = ../../external-packages;
        pkgs = stablePkgs;
        inherit edgePackages;
        edgePkgs = unstablePkgs;
      };
    in
    custom
    // external
    // {
      cpa-usage-keeper-web = external.cpa-usage-keeper.web;
      lyricsctl = custom.bunjs-lyrics;
      grok = inputs.llm-agents.packages.${stablePkgs.stdenv.hostPlatform.system}.grok;
    };
in
{
  flake = {
    overlays.customPackages = final: _prev: {
      customPackages = getPackages {
        stablePkgs = final;
        unstablePkgs = final.unstable;
      };
    };

    packageSets = {
      custom = customPackageNames;
      external = externalPackageNames ++ [ "grok" ];
      edge = edgePackages;
    };
  };

  perSystem =
    { pkgs, ... }:
    {
      packages = getPackages {
        stablePkgs = pkgs;
        unstablePkgs = pkgs.unstable;
      };

      checks.update-pkgs-workflow-coverage = pkgs.runCommandLocal "update-pkgs-workflow-coverage" { } ''
        : ${builtins.toString coverageCheck}
        mkdir -p "$out"
      '';
    };
}
