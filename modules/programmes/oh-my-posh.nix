{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      theme = "$FLAKE/modules/programmes/oh-my-posh/settings.json";
    in
    {
      packages.oh-my-posh = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.oh-my-posh;
        env = {
          POSH_THEME = theme;
        };
        passthru = {
          inherit theme;
        };
      };
    };
}
