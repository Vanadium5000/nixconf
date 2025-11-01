{ self, ... }:
let
  inherit (self) colors theme;
in
{
  perSystem =
    {
      pkgs,
      self',
      ...
    }:
    {
      packages.terminal = self'.packages.kitty;

      packages.kitty = self.wrapperModules.kitty.apply {
        inherit pkgs;
        config = {
          enable_audio_bell = "no";

          font_size = 15;

          cursor_text_color = "background";

          allow_remote_control = "yes";
          shell_integration = "enabled";

          cursor_trail = 3;

          background = colors.base00;
          foreground = colors.base07;
          background_opacity = theme.opacity;

          cursor = colors.base07;

          selection_foreground = colors.base02;
          selection_background = colors.base01;

          color0 = colors.base00;
          color8 = colors.base02;
          color1 = colors.base08;
          color9 = colors.base08;
          color2 = colors.base0B;
          color10 = colors.base0B;
          color3 = colors.base0A;
          color11 = colors.base0A;
          color4 = colors.base0D;
          color12 = colors.base0D;
          color5 = colors.base0E;
          color13 = colors.base0E;
          color6 = colors.base0C;
          color14 = colors.base0C;
          color7 = colors.base03;
          color15 = colors.base03;
        };
      };
    };
}
