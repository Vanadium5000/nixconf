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
      hyprqt6enginePackage =
        inputs.hyprqt6engine.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs
          (old: {
            buildInputs = old.buildInputs ++ [
              # hyprqt6engine only enables .colors palette support when KF6
              # KConfig/KColorScheme targets exist at build time. Source:
              # /nix/store/1fy0i6lzasn8vc7q0yksv983j286bgqn-source/common/CMakeLists.txt:11
              pkgs.kdePackages.kconfig
              pkgs.kdePackages.kcolorscheme

              # Optional build targets let hyprqt6engine integrate KDE icons and set
              # Qt Quick Controls' desktop style itself when a QWidget app starts.
              # Source: /nix/store/1fy0i6lzasn8vc7q0yksv983j286bgqn-source/hyprqtplugin/CMakeLists.txt:13
              pkgs.kdePackages.kiconthemes
              pkgs.qt6Packages.qtdeclarative
            ];
          });
      kdeColorSchemeId = "NixCyberpunkElectricDark";
      kdeColorSchemeName = "Nix Cyberpunk Electric Dark";

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
      kdeColorSchemeText = ''
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
        ColorScheme=${kdeColorSchemeId}
        Name=${kdeColorSchemeName}
        shadeSortColumn=true

        [KDE]
        contrast=4

        # KF6 selects the active scheme through UiSettings/ColorScheme, while
        # General/ColorScheme is ignored for that purpose. Source:
        # https://github.com/KDE/kcolorscheme/blob/8ca396afd9ee592b18c705236db6c376804817af/src/kcolorschememanager.cpp#L181-L214
        [UiSettings]
        ColorScheme=${kdeColorSchemeId}

        [WM]
        activeBackground=${rgb "base01"}
        activeBlend=${rgb "base07"}
        activeForeground=${rgb "base07"}
        inactiveBackground=${rgb "base00"}
        inactiveBlend=${rgb "base05"}
        inactiveForeground=${rgb "base05"}
      '';
      hyprqt6engineColorScheme = pkgs.writeText "nixconf-hyprqt6engine.colors" kdeColorSchemeText;

      user = config.preferences.user.username;

      # The config path and keys are hyprqt6engine's documented interface.
      # Source: https://wiki.hypr.land/Hypr-Ecosystem/hyprqt6engine/
      hyprqt6engineConf = self.lib.generators.toHyprconf {
        attrs = {
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
            single_click_activate = 1;
            menus_have_icons = 1;
            shortcuts_for_context_menus = 1;
          };
        };
      };

      # KDE/Kirigami apps read palette selection from kdeglobals, so reuse the
      # full generated scheme here instead of only writing [General]. Trace:
      # /tmp/plasma-systemmonitor-live-theme.trace. The same file stays published
      # below in XDG color-schemes for discovery/UI use.
      kdeGlobals = kdeColorSchemeText;
    in
    {
      qt.enable = true;

      environment.sessionVariables = {
        QT_QPA_PLATFORM = "wayland";
        QT_QPA_PLATFORMTHEME = "hyprqt6engine";

        # Kirigami defaults to Qt Quick Controls' Fusion style outside Plasma;
        # selecting KDE's desktop style lets it match the installed plugin.
        # Source: https://invent.kde.org/frameworks/qqc2-desktop-style/-/blob/master/README.md
        QT_QUICK_CONTROLS_STYLE = "org.kde.desktop";

        # Assumption: Oxygen is a KDE style, so these markers keep KDE code paths
        # active outside Plasma rather than falling back to generic integration.
        KDE_FULL_SESSION = "true";
        KDE_SESSION_VERSION = "6";
      };

      # Add the package's Qt root as a profile-relative suffix so NixOS still
      # appends its generated lib/qt-6/plugins entries. Sources:
      # - /nix/store/fm3z9r7r90yh8l7ai6cn6gsrp6h27ira-source/nixos/modules/config/qt.nix:220
      # - /home/matrix/.local/share/opencode/tool-output/tool_df57a1f13001uFteU5BjvMikVt
      environment.profileRelativeSessionVariables.QT_PLUGIN_PATH = [ "/lib/qt-6" ];

      environment.systemPackages = with pkgs; [
        kdePackages.oxygen
        kdePackages.oxygen-icons
        hyprqt6enginePackage

        # Freedesktop fallbacks keep Qt icon lookup working when Oxygen lacks an
        # application/action name. Source: https://doc.qt.io/qt-6/qicon.html#fromTheme
        hicolor-icon-theme
        adwaita-icon-theme
      ];

      system.activationScripts.qt-user-files = {
        text = self.lib.userFiles.mkActivationScript {
          inherit user;
          inherit pkgs;
          homeDirectory = config.preferences.paths.homeDirectory;
          files = {
            ".config/hypr/hyprqt6engine.conf".text = hyprqt6engineConf;
            ".config/kdeglobals".text = kdeGlobals;
            ".local/share/color-schemes/${kdeColorSchemeId}.colors".source = hyprqt6engineColorScheme;
          };
        };
        deps = [ "users" ];
      };
    };
}
