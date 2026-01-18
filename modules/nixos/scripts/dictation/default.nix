{ inputs, ... }:
{
  flake.nixosModules.dictation =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      cfg = config.preferences.dictation;
    in
    {
      options.preferences.dictation = {
        enable = lib.mkEnableOption "Dictation system";
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [
          inputs.self.packages.${pkgs.system}.dictation
        ];

        systemd.user.services.dictation = {
          description = "Dictation Daemon";
          wantedBy = [ "graphical-session.target" ];
          partOf = [ "graphical-session.target" ];
          serviceConfig = {
            ExecStart = "${inputs.self.packages.${pkgs.system}.dictation}/bin/dictation daemon";
            Restart = "always";
            RestartSec = "5";
          };
        };
      };
    };
}
