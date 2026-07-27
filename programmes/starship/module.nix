{ inputs, self, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      theme = self.themes.mainTheme;
    in
    {
      packages.starship = inputs.wrappers.wrappers.starship.wrap {
        inherit pkgs;
        settings = {
          add_newline = true;
          palette = "nixconf";
          palettes.nixconf = {
            background = theme.palette.background;
            foreground = theme.palette.foregroundAlt;
            accent = theme.palette.accentAlt;
            warning = theme.palette.warning;
            error = theme.palette.error;
            success = theme.palette.success;
          };
          character = {
            success_symbol = "[❯](accent)";
            error_symbol = "[❯](error)";
          };
          directory.style = "bold accent";
          git_branch.style = "accent";
          git_status.style = "warning";
        };
      };

    };
}
