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
      dmsProgram = config.programs.dank-material-shell;

      # DMS is a graphical user-session shell, not a system daemon; upstream
      # wires it to this target from its NixOS module. Source:
      # https://github.com/AvengeMedia/DankMaterialShell/blob/eb5afcdc40ea5446c27e18552ff4a19f9daf9484/distro/nix/nixos.nix#L21-L43
      graphicalSessionTarget = "graphical-session.target";
    in
    {
      imports = [
        inputs.dms.nixosModules.dank-material-shell
      ];

      options.preferences.dankMaterialShell = {
        enable = lib.mkEnableOption "DankMaterialShell desktop shell";
      };

      config = lib.mkIf cfg.enable {
        assertions = [
          {
            assertion = config.systemd.user.services ? dms;
            message = "DankMaterialShell must expose systemd.user.services.dms when preferences.dankMaterialShell.enable is true.";
          }
          {
            assertion = lib.elem graphicalSessionTarget config.systemd.user.services.dms.wantedBy;
            message = "DankMaterialShell dms.service must be wanted by ${graphicalSessionTarget}.";
          }
        ];

        # Keep the upstream option behind a local preference so hosts can opt in
        # without learning DMS's flake-module namespace. Source:
        # https://danklinux.com/docs/dankmaterialshell/nixos
        programs.dank-material-shell = {
          enable = true;
          package = pkgs.unstable.dms-shell;
          dgop.package = pkgs.unstable.dgop;
          systemd = {
            enable = true;
            target = graphicalSessionTarget;
          };
          enableSystemMonitoring = true;
          enableDynamicTheming = true;
          enableAudioWavelength = true;
          enableClipboardPaste = true;
        };

        # Mirror the upstream user unit locally so installing `dms-shell` cannot
        # be mistaken for a runnable shell service if upstream wiring changes.
        # mkDefault keeps the imported DMS module authoritative when present.
        systemd.user.services.dms = {
          description = lib.mkDefault "DankMaterialShell";
          wantedBy = lib.mkDefault [ graphicalSessionTarget ];
          partOf = lib.mkDefault [ graphicalSessionTarget ];
          after = lib.mkDefault [ graphicalSessionTarget ];

          serviceConfig = {
            ExecStart = lib.mkDefault "${lib.getExe dmsProgram.package} run --session";
            Restart = lib.mkDefault "on-failure";
          };
        };
      };
    };
}
