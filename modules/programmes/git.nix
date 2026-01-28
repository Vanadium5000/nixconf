{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      packages.git = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.git;
      };
    };
}
