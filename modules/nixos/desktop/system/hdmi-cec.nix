{ self, ... }:
{
  flake.nixosModules.hdmi-cec =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    let
      cfg = lib.attrByPath [ "preferences" "hardware" "hdmiCec" ] { enable = false; } config;

      cecSetup = pkgs.writeShellApplication {
        name = "nixconf-hdmi-cec-setup";
        runtimeInputs = [ pkgs.v4l-utils ];
        text = ''
          set -euo pipefail

          status=0
          for dev in /dev/cec*; do
            [ -e "$dev" ] || continue

            if ! cec-ctl --device "$dev" --playback --osd-name nixconf; then
              status=1
            fi
          done

          exit "$status"
        '';
      };
    in
    {
      options.preferences.hardware.hdmiCec.enable = lib.mkEnableOption "HDMI-CEC remote media controls";

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ pkgs.v4l-utils ];

        services.udev.extraRules = ''
          ACTION=="add|change", SUBSYSTEM=="cec", TAG+="systemd", ENV{SYSTEMD_WANTS}+="nixconf-hdmi-cec-setup.service"
        '';

        # Register every /dev/cec* adapter as a CEC Playback device so TVs route
        # USER_CONTROL_PRESSED remote keys through the kernel RC passthrough map.
        # Source: https://docs.kernel.org/admin-guide/media/cec.html#displayport-to-hdmi-adapters-with-working-cec
        systemd.services.nixconf-hdmi-cec-setup = {
          description = "Configure HDMI-CEC playback remote controls";
          wantedBy = [ "multi-user.target" ];
          after = [ "systemd-udevd.service" ];

          serviceConfig = {
            Type = "oneshot";
            ExecStart = lib.getExe cecSetup;
          };
        };
      };
    };
}
