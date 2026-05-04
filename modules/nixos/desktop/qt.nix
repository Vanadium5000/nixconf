{ inputs, self, ... }:
{
  flake.nixosModules.qt =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      inherit (self) colorsRgbaValues theme;

      rgb =
        name:
        let
          value = colorsRgbaValues.${name};
        in
        "${builtins.toString (builtins.elemAt value 0)},${builtins.toString (builtins.elemAt value 1)},${builtins.toString (builtins.elemAt value 2)}";

      # hyprqt6engine treats .colors files as KDE KColorSchemes, so generating
      # one keeps Qt palettes tied directly to modules/theme.nix. Sources:
      # - https://github.com/hyprwm/hyprqt6engine/blob/main/common/common.cpp
      # - https://github.com/hyprwm/hyprqt6engine/blob/main/hyprqtplugin/PlatformTheme.cpp
      hyprqt6engineColorScheme = pkgs.writeText "nixconf-hyprqt6engine.colors" ''
        # KDE color schemes use the same KColorScheme section layout as Breeze.
        # Keeping that structure lets Qt/KDE apps and hyprqt6engine consume the
        # generated palette directly. Sources:
        # - https://github.com/KDE/breeze/blob/master/colors/BreezeDark.colors
        [ColorEffects:Disabled]
        Color=${rgb "base03"}
        ColorAmount=0
        ColorEffect=0
        ContrastAmount=0.65
        ContrastEffect=1
        IntensityAmount=0.1
        IntensityEffect=2

        [ColorEffects:Inactive]
        ChangeSelectionColor=true
        Color=${rgb "base04"}
        ColorAmount=0.025
        ColorEffect=2
        ContrastAmount=0.1
        ContrastEffect=2
        Enable=false
        IntensityAmount=0
        IntensityEffect=0

        [Colors:Button]
        BackgroundAlternate=${rgb "base02"}
        BackgroundNormal=${rgb "base01"}
        DecorationFocus=${rgb "base0D"}
        DecorationHover=${rgb "base0C"}
        ForegroundActive=${rgb "base07"}
        ForegroundInactive=${rgb "base05"}
        ForegroundLink=${rgb "base0D"}
        ForegroundNegative=${rgb "base08"}
        ForegroundNeutral=${rgb "base09"}
        ForegroundNormal=${rgb "base07"}
        ForegroundPositive=${rgb "base0B"}
        ForegroundVisited=${rgb "base0E"}

        [Colors:Complementary]
        BackgroundAlternate=${rgb "base02"}
        BackgroundNormal=${rgb "base01"}
        DecorationFocus=${rgb "base0D"}
        DecorationHover=${rgb "base0C"}
        ForegroundActive=${rgb "base07"}
        ForegroundInactive=${rgb "base05"}
        ForegroundLink=${rgb "base0D"}
        ForegroundNegative=${rgb "base08"}
        ForegroundNeutral=${rgb "base09"}
        ForegroundNormal=${rgb "base05"}
        ForegroundPositive=${rgb "base0B"}
        ForegroundVisited=${rgb "base0E"}

        [Colors:Header]
        BackgroundAlternate=${rgb "base02"}
        BackgroundNormal=${rgb "base01"}
        DecorationFocus=${rgb "base0D"}
        DecorationHover=${rgb "base0C"}
        ForegroundActive=${rgb "base07"}
        ForegroundInactive=${rgb "base05"}
        ForegroundLink=${rgb "base0D"}
        ForegroundNegative=${rgb "base08"}
        ForegroundNeutral=${rgb "base09"}
        ForegroundNormal=${rgb "base07"}
        ForegroundPositive=${rgb "base0B"}
        ForegroundVisited=${rgb "base0E"}

        [Colors:Header][Inactive]
        BackgroundAlternate=${rgb "base01"}
        BackgroundNormal=${rgb "base00"}
        DecorationFocus=${rgb "base0D"}
        DecorationHover=${rgb "base0C"}
        ForegroundActive=${rgb "base07"}
        ForegroundInactive=${rgb "base05"}
        ForegroundLink=${rgb "base0D"}
        ForegroundNegative=${rgb "base08"}
        ForegroundNeutral=${rgb "base09"}
        ForegroundNormal=${rgb "base05"}
        ForegroundPositive=${rgb "base0B"}
        ForegroundVisited=${rgb "base0E"}

        [Colors:Selection]
        BackgroundAlternate=${rgb "base0C"}
        BackgroundNormal=${rgb "base0D"}
        DecorationFocus=${rgb "base0D"}
        DecorationHover=${rgb "base0C"}
        ForegroundActive=${rgb "base07"}
        ForegroundInactive=${rgb "base05"}
        ForegroundLink=${rgb "base0C"}
        ForegroundNegative=${rgb "base08"}
        ForegroundNeutral=${rgb "base0A"}
        ForegroundNormal=${rgb "base07"}
        ForegroundPositive=${rgb "base0B"}
        ForegroundVisited=${rgb "base0E"}

        [Colors:Tooltip]
        BackgroundAlternate=${rgb "base02"}
        BackgroundNormal=${rgb "base01"}
        DecorationFocus=${rgb "base0D"}
        DecorationHover=${rgb "base0C"}
        ForegroundActive=${rgb "base07"}
        ForegroundInactive=${rgb "base05"}
        ForegroundLink=${rgb "base0D"}
        ForegroundNegative=${rgb "base08"}
        ForegroundNeutral=${rgb "base09"}
        ForegroundNormal=${rgb "base07"}
        ForegroundPositive=${rgb "base0B"}
        ForegroundVisited=${rgb "base0E"}

        [Colors:View]
        BackgroundAlternate=${rgb "base01"}
        BackgroundNormal=${rgb "base00"}
        DecorationFocus=${rgb "base0D"}
        DecorationHover=${rgb "base0C"}
        ForegroundActive=${rgb "base07"}
        ForegroundInactive=${rgb "base05"}
        ForegroundLink=${rgb "base0D"}
        ForegroundNegative=${rgb "base08"}
        ForegroundNeutral=${rgb "base09"}
        ForegroundNormal=${rgb "base05"}
        ForegroundPositive=${rgb "base0B"}
        ForegroundVisited=${rgb "base0E"}

        [Colors:Window]
        BackgroundAlternate=${rgb "base01"}
        BackgroundNormal=${rgb "base00"}
        DecorationFocus=${rgb "base0D"}
        DecorationHover=${rgb "base0C"}
        ForegroundActive=${rgb "base07"}
        ForegroundInactive=${rgb "base05"}
        ForegroundLink=${rgb "base0D"}
        ForegroundNegative=${rgb "base08"}
        ForegroundNeutral=${rgb "base09"}
        ForegroundNormal=${rgb "base05"}
        ForegroundPositive=${rgb "base0B"}
        ForegroundVisited=${rgb "base0E"}

        [General]
        ColorScheme=NixCyberpunkElectricDark
        Name=Nix Cyberpunk Electric Dark
        shadeSortColumn=true

        [KDE]
        contrast=4

        [WM]
        activeBackground=${rgb "base01"}
        activeBlend=${rgb "base07"}
        activeForeground=${rgb "base07"}
        inactiveBackground=${rgb "base00"}
        inactiveBlend=${rgb "base05"}
        inactiveForeground=${rgb "base05"}
      '';

      user = config.preferences.user.username;

      # The config path and keys are hyprqt6engine's documented interface.
      # Source: https://wiki.hypr.land/Hypr-Ecosystem/hyprqt6engine/
      hyprqt6engineConf = lib.generators.toINI { } {
        theme = {
          style = "Oxygen";
          icon_theme = "oxygen";
          font = theme.font;
          font_size = theme."font-size";
          font_fixed = theme.font;
          font_fixed_size = theme.system."font-size";
          color_scheme = hyprqt6engineColorScheme;
        };
        misc = {
          single_click_activate = true;
          menus_have_icons = true;
        };
      };
    in
    {
      qt.enable = true;

      environment.variables = {
        QT_QPA_PLATFORM = "wayland";
        QT_QPA_PLATFORMTHEME = "hyprqt6engine";

        # Assumption: Oxygen is a KDE style, so these markers keep KDE code paths
        # active outside Plasma rather than falling back to generic integration.
        KDE_FULL_SESSION = "true";
        KDE_SESSION_VERSION = "6";
      };

      environment.systemPackages = with pkgs; [
        kdePackages.oxygen
        kdePackages.oxygen-icons
        inputs.hyprqt6engine.packages.${pkgs.stdenv.hostPlatform.system}.default

        # Freedesktop fallbacks keep Qt icon lookup working when Oxygen lacks an
        # application/action name. Source: https://doc.qt.io/qt-6/qicon.html#fromTheme
        hicolor-icon-theme
        adwaita-icon-theme
      ];

      hjem.users.${user} = {
        files.".config/hypr/hyprqt6engine.conf".text = hyprqt6engineConf;
      };
    };
}
