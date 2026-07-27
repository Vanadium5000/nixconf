{ inputs, self, ... }:
let
  workflow = import ../../external-packages/update-pkgs/workflow.nix;
  edgePackages = workflow.edgePackages;
  modulePackageNames = [
    "models"
    "qs-menus"
  ];
  customPackageNames = self.lib.packages.directoryNamesWithPackage ../.;
  externalPackageNames = self.lib.packages.directoryNamesWithPackage ../../external-packages;
  coverageCheck = self.lib.packages.warnOnMissingCoverage {
    packageNames = externalPackageNames;
    coveredNames = builtins.attrNames workflow.updateModes;
    context = "external-packages";
  };
  architectureCheck = self.lib.packages.warnOnUnexpectedRootEntries {
    roots = {
      docs = {
        allowed = [ ];
        expectedType = "directory";
      };
      external-packages = {
        allowed = [ ];
        expectedType = "directory";
      };
      hosts = {
        allowed = [ ];
        expectedType = "directory";
      };
      modules = {
        allowed = [ ];
        expectedType = "directory";
      };
      packages = {
        allowed = [ ];
        expectedType = "directory";
      };
      programmes = {
        allowed = [ ];
        expectedType = "directory";
      };
    };
  };

  packageDirectoryCheck = self.lib.packages.warnOnPackageDirectoryContract {
    roots = {
      packages = {
        # _exports is flake plumbing, never an installable package directory.
        allowedDirectories = [ "_exports" ];
        requiredFile = "package.nix";
      };
      external-packages = {
        requiredFile = "package.nix";
      };
      programmes = {
        requiredFiles = [
          "module.nix"
          "package.nix"
        ];
      };
    };
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
        packageArgs =
          name:
          if
            builtins.elem name [
              "bunjs-music-local"
              "bunjs-music-search"
              "bunjs-passmenu"
            ]
          then
            {
              # These command packages consume only qs-dmenu, not the full menu
              # suite. It is a direct flake export from qs-menus/package.nix.
              qs-dmenu = self.packages.${stablePkgs.stdenv.hostPlatform.system}.qs-dmenu;
            }
          else
            { };
      };
      external = self.lib.packages.callDirectoryPackages {
        root = ../../external-packages;
        pkgs = stablePkgs;
        inherit edgePackages;
        edgePkgs = unstablePkgs;
      };
    in
    (builtins.removeAttrs custom [ "repo-audits" ])
    // external
    // {
      cpa-usage-keeper-web = external.cpa-usage-keeper.web;
      persist-audit = custom.repo-audits.persist-audit;
      nix-unused-audit = custom.repo-audits.nix-unused-audit;
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

      checks.repository-architecture = pkgs.runCommandLocal "repository-architecture" { } ''
        : ${builtins.toString architectureCheck}
        : ${builtins.toString packageDirectoryCheck}
        mkdir -p "$out"
      '';
    };
}
