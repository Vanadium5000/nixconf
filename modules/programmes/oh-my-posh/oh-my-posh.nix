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
          POSH_NO_TERM_QUERIES = "1";
        };
        passthru = {
          inherit theme;
        };
      };
    };
}
