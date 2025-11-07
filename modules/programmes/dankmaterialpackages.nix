{ inputs, ... }:
{
  perSystem =
    { system, ... }:
    let
      # Aggregate packages from input flakes
      # - dankMaterialShell: Built from source in its repo (assets/configs for Quickshell)
      # - dmsCli: Default package from danklinux repo (CLI tool for DMS management)
      # - dgop: Specific 'dgop' package from dgop repo (monitoring daemon)
      dmsPkgs = {
        dankMaterialShell = inputs.dankMaterialShell.packages.${system}.default;
        dmsCli = inputs.dms-cli.packages.${system}.default;
        dgop = inputs.dgop.packages.${system}.dgop;
      };
    in
    {
      # Export individual packages for direct access
      packages = {
        dankMaterialShell = dmsPkgs.dankMaterialShell;
        dmsCli = dmsPkgs.dmsCli;
        dgop = dmsPkgs.dgop;
      };
    };
}
