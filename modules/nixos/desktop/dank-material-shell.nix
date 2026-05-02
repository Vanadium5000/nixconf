{ inputs, ... }:
{
  flake.nixosModules.dankmemershell =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.preferences.dankMaterialShell;
    in
    {
      imports = [
        inputs.dms.nixosModules.dank-material-shell
      ];

      options.preferences.dankMaterialShell = {
        enable = lib.mkEnableOption "DankMaterialShell desktop shell";
      };

      config = lib.mkIf cfg.enable {
        # Keep the upstream option behind a local preference so hosts can opt in
        # without learning DMS's flake-module namespace. Source:
        # https://danklinux.com/docs/dankmaterialshell/nixos
        programs.dank-material-shell = {
          enable = true;
          package = pkgs.unstable.dms-shell;
          dgop.package = pkgs.unstable.dgop;
          systemd.enable = true;
          enableSystemMonitoring = true;
          enableDynamicTheming = true;
          enableAudioWavelength = true;
          enableClipboardPaste = true;
        };
      };
    };
}
