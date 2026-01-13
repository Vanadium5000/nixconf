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
          color_scheme = "${pkgs.kdePackages.qt6ct}/share/qt6ct/colors/darker.conf";
          font = "JetBrainsMono Nerd Font";
          font_size = 11;
          font_fixed = "JetBrainsMono Nerd Font";
          font_fixed_size = 11;
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
      };

      environment.systemPackages = with pkgs; [
        kdePackages.oxygen
        kdePackages.oxygen-icons
        inputs.hyprqt6engine.packages.${pkgs.stdenv.hostPlatform.system}.default
      ];

      hjem.users.${user} = {
        files.".config/hypr/hyprqt6engine.conf".text = hyprqt6engineConf;
      };
    };
}
