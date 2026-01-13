{ ... }:
{
  flake.nixosModules.qt =
    { pkgs, ... }:
    {
      qt = {
        enable = true;
        platformTheme = "qt5ct";
      };

      environment.variables = {
        QT_QPA_PLATFORM = "wayland";
        QT_QPA_PLATFORMTHEME = "qt5ct";
        QT_STYLE_OVERRIDE = "oxygen";
      };

      environment.systemPackages = with pkgs; [
        kdePackages.oxygen
        kdePackages.oxygen-icons
        kdePackages.qt6ct
        libsForQt5.qt5ct
      ];
    };
}
