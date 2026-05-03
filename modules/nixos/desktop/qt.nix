{ ... }:
{
  flake.nixosModules.qt =
    {
      pkgs,
      ...
    }:
    {
      qt.enable = true;

      environment.variables = {
        QT_QPA_PLATFORM = "wayland";
        # DMS's Qt theme applier writes qtct configs and checks this variable
        # before applying colors. Source:
        # https://github.com/AvengeMedia/DankMaterialShell/blob/eb5afcdc40ea5446c27e18552ff4a19f9daf9484/quickshell/scripts/qt.sh#L53-L64
        QT_QPA_PLATFORMTHEME = "qt6ct";
        QT_QPA_PLATFORMTHEME_QT6 = "qt6ct";
      };

      environment.systemPackages = with pkgs; [
        # DMS generates qt6ct and qt5ct color files, so install both frontends
        # rather than declaring a custom Hyprland Qt engine in this repo.
        # Source:
        # https://github.com/AvengeMedia/DankMaterialShell/blob/eb5afcdc40ea5446c27e18552ff4a19f9daf9484/quickshell/Modules/Settings/ThemeColorsTab.qml#L2603-L2604
        kdePackages.qt6ct
        libsForQt5.qt5ct
      ];

      impermanence.home.directories = [
        ".config/qt5ct"
        ".config/qt6ct"
        # DMS writes DankMatugen.colors here before qtct configs reference it.
        # Source: quickshell/scripts/qt.sh builds ~/.local/share/color-schemes.
        ".local/share/color-schemes"
      ];
    };
}
