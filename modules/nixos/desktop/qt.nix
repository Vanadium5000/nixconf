{ ... }:
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

      qt5ctConf = lib.generators.toINI {
        Appearance = {
          style = "Oxygen";
          icon_theme = "oxygen";
          custom_palette = true;
          color_scheme_path = "${pkgs.kdePackages.qt6ct}/share/qt6ct/colors/darker.conf";
          standard_dialogs = "default";
        };
        Troubleshooting = {
          ignored_applications = "@Invalid()";
        };
      };
    in
    {
      qt = {
        enable = true;
        platformTheme = "qt5ct";
      };

      environment.variables = {
        QT_QPA_PLATFORM = "wayland";
        QT_QPA_PLATFORMTHEME = "qt5ct";
      };

      environment.systemPackages = with pkgs; [
        kdePackages.oxygen
        kdePackages.oxygen-icons
        kdePackages.qt6ct
        libsForQt5.qt5ct
      ];

      hjem.users.${user} = {
        files.".config/qt5ct/qt5ct.conf".text = qt5ctConf;
        files.".config/qt6ct/qt6ct.conf".text = qt5ctConf;
      };
    };
}
