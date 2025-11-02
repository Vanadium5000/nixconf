{
  flake.nixosModules.wallpaper =
    {
      pkgs,
      lib,
      ...
    }:
    let
      inherit (lib) getExe;
    in
    {
      preferences.autostart = [
        ''
          ${pkgs.swww}/bin/swww-daemon &
          ${getExe pkgs.swww} img ${pkgs.nixy-wallpapers}/wallpapers/fuji-dark.png &
        ''
      ];
    };
}
