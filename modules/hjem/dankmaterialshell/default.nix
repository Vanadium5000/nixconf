{
  flake.nixosModules.extra_hjem =
    {
      ...
    }:
    {
      home.programs.dankMaterialShell = {
        enable = true;
        systemd.enable = true;
      };
    };
}
