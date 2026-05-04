{ inputs, ... }:
{
  flake.nixosModules.qt =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      user = config.preferences.user.username;

      hyprqt6engineConf = lib.generators.toINI { } {
        theme = {
          style = "Oxygen";
          icon_theme = "oxygen";
          font = "JetBrainsMono Nerd Font";
          font_size = 12;
          font_fixed = "JetBrainsMono Nerd Font";
          font_fixed_size = 12;
          color_scheme = "${pkgs.kdePackages.breeze}/share/color-schemes/BreezeDark.colors";
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
        # Help Oxygen style detect proper environment
        KDE_FULL_SESSION = "true";
        KDE_SESSION_VERSION = "6";
        # Force the color scheme path in case the engine fails to apply it from config
        KDE_COLOR_SCHEME_PATH = "${pkgs.kdePackages.breeze}/share/color-schemes/BreezeDark.colors";
      };

      environment.systemPackages = with pkgs; [
        kdePackages.oxygen
        kdePackages.oxygen-icons
        kdePackages.breeze # Required for BreezeDark.colors
        inputs.hyprqt6engine.packages.${pkgs.stdenv.hostPlatform.system}.default
      ];

      hjem.users.${user} = {
        files.".config/hypr/hyprqt6engine.conf".text = hyprqt6engineConf;
      };
    };
}
