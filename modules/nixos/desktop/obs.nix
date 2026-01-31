{ self, ... }:
{
  flake.nixosModules.obs =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.preferences.obs;
    in
    {
      options.preferences.obs = {
        enable = lib.mkEnableOption "OBS Studio";
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ pkgs.obs-studio ];

        # Enable the v4l2loopback kernel module for virtual camera support
        boot.extraModulePackages = [ config.boot.kernelPackages.v4l2loopback ];
        boot.kernelModules = [ "v4l2loopback" ];
        
        # exclusive_caps=1 is often needed for Chrome/WebRTC compatibility
        boot.extraModprobeConfig = ''
          options v4l2loopback devices=1 video_nr=1 card_label="OBS Virtual Camera" exclusive_caps=1
        '';
      };
    };
}
