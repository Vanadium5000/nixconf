{ inputs, self, ... }:
{
  flake.ohMyPosh = {
    themeFile = self.lib.configFiles.known.ohMyPoshTheme;
  };

  perSystem =
    { pkgs, ... }:
    let
      theme = self.ohMyPosh.themeFile.storePath;
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
