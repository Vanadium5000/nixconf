{
  self,
  lib,
  ...
}:
{
  perSystem =
    { pkgs, ... }:
    let
      mkColorScheme =
        theme:
        let
          inherit (theme) colors scheme;
          color = value: lib.removePrefix "#" value;
        in
        pkgs.runCommand "${scheme}.colors" { } ''
          mkdir -p "$out/share/color-schemes"
          cat > "$out/share/color-schemes/${scheme}.colors" <<'EOF'
          [ColorEffects:Disabled]
          Color=${color colors.base03}
          ColorAmount=0
          ColorEffect=0
          ContrastAmount=0.65
          ContrastEffect=1
          IntensityAmount=0.1
          IntensityEffect=2

          [ColorEffects:Inactive]
          ChangeSelectionColor=true
          Color=${color colors.base03}
          ColorAmount=0.025
          ColorEffect=2
          ContrastAmount=0.1
          ContrastEffect=2
          Enable=true
          IntensityAmount=0
          IntensityEffect=0

          [Colors:Button]
          BackgroundAlternate=${color colors.base01}
          BackgroundNormal=${color colors.base01}
          DecorationFocus=${color colors.base0D}
          DecorationHover=${color colors.base0C}
          ForegroundActive=${color colors.base0D}
          ForegroundInactive=${color colors.base04}
          ForegroundLink=${color colors.base0C}
          ForegroundNegative=${color colors.base08}
          ForegroundNeutral=${color colors.base0A}
          ForegroundNormal=${color colors.base05}
          ForegroundPositive=${color colors.base0B}
          ForegroundVisited=${color colors.base0E}

          [Colors:Selection]
          BackgroundAlternate=${color colors.base0D}
          BackgroundNormal=${color colors.base0D}
          DecorationFocus=${color colors.base0C}
          DecorationHover=${color colors.base0C}
          ForegroundActive=${color colors.base07}
          ForegroundInactive=${color colors.base06}
          ForegroundLink=${color colors.base0C}
          ForegroundNegative=${color colors.base08}
          ForegroundNeutral=${color colors.base0A}
          ForegroundNormal=${color colors.base07}
          ForegroundPositive=${color colors.base0B}
          ForegroundVisited=${color colors.base0E}

          [Colors:Tooltip]
          BackgroundAlternate=${color colors.base01}
          BackgroundNormal=${color colors.base01}
          DecorationFocus=${color colors.base0D}
          DecorationHover=${color colors.base0C}
          ForegroundActive=${color colors.base0D}
          ForegroundInactive=${color colors.base04}
          ForegroundLink=${color colors.base0C}
          ForegroundNegative=${color colors.base08}
          ForegroundNeutral=${color colors.base0A}
          ForegroundNormal=${color colors.base05}
          ForegroundPositive=${color colors.base0B}
          ForegroundVisited=${color colors.base0E}

          [Colors:View]
          BackgroundAlternate=${color colors.base01}
          BackgroundNormal=${color colors.base00}
          DecorationFocus=${color colors.base0D}
          DecorationHover=${color colors.base0C}
          ForegroundActive=${color colors.base0D}
          ForegroundInactive=${color colors.base04}
          ForegroundLink=${color colors.base0C}
          ForegroundNegative=${color colors.base08}
          ForegroundNeutral=${color colors.base0A}
          ForegroundNormal=${color colors.base05}
          ForegroundPositive=${color colors.base0B}
          ForegroundVisited=${color colors.base0E}

          [Colors:Window]
          BackgroundAlternate=${color colors.base01}
          BackgroundNormal=${color colors.base00}
          DecorationFocus=${color colors.base0D}
          DecorationHover=${color colors.base0C}
          ForegroundActive=${color colors.base0D}
          ForegroundInactive=${color colors.base04}
          ForegroundLink=${color colors.base0C}
          ForegroundNegative=${color colors.base08}
          ForegroundNeutral=${color colors.base0A}
          ForegroundNormal=${color colors.base05}
          ForegroundPositive=${color colors.base0B}
          ForegroundVisited=${color colors.base0E}

          [General]
          ColorScheme=${scheme}
          Name=${theme.name}
          shadeSortColumn=true
          EOF
        '';
    in
    {
      packages.kde-color-schemes = pkgs.symlinkJoin {
        name = "nixconf-kde-colour-schemes";
        paths = builtins.attrValues (builtins.mapAttrs (_: mkColorScheme) self.themes.registry);
      };
    };
}
