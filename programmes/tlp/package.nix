{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      packages.tlp = inputs.wrappers.lib.wrapPackage {
        inherit pkgs;
        package = pkgs.tlp;
        runtimePkgs = [ pkgs.coreutils ];
      };
    };
}
