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
        };
        Palette = {
          Window = "#232629";
          WindowText = "#eff0f1";
          Base = "#1b1e20";
          AlternateBase = "#232629";
          Button = "#31363b";
          ButtonText = "#eff0f1";
          Highlight = "#3daee9";
          HighlightedText = "#eff0f1";
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
