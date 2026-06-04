{ ... }:
{
  flake.nixosModules.tlp =
    { lib, config, ... }:
    let
      cfg = lib.attrByPath [ "preferences" "hardware" "tlp" ] { enable = false; } config;
      chargeSettings = {
        none = { };
        lenovo-conservation = {
          # Lenovo non-ThinkPads expose conservation mode, not arbitrary
          # thresholds: START is a dummy and STOP=1 enables the fixed 60/80%
          # hardware target depending on model/kernel.
          # Source: https://linrunner.de/tlp/settings/bc-vendors.html#lenovo-non-thinkpad-series
          START_CHARGE_THRESH_BAT0 = 0;
          STOP_CHARGE_THRESH_BAT0 = 1;
        };
      };
    in
    {
      config = lib.mkIf cfg.enable {
        # TLP owns power policy on laptop hosts so desktop daemons do not fight it.
        services.tlp = {
          enable = true;
          settings = {
            # The processor selects frequencies autonomously inside these policy rails.
            CPU_DRIVER_OPMODE_ON_AC = "active";
            CPU_DRIVER_OPMODE_ON_BAT = "active";

            # Keep governor predictable while letting the energy policy do the heavy lifting.
            CPU_SCALING_GOVERNOR_ON_AC = "powersave";
            CPU_SCALING_GOVERNOR_ON_BAT = "powersave";

            # Battery mode favors cooler sustained performance over short burst speed.
            CPU_ENERGY_PERF_POLICY_ON_AC = "balance_performance";
            CPU_ENERGY_PERF_POLICY_ON_BAT = "power";

            # Turbo is worth keeping on AC, but it is a poor battery trade-off here.
            CPU_BOOST_ON_AC = 1;
            CPU_BOOST_ON_BAT = 0;

            CPU_HWP_DYN_BOOST_ON_AC = 1;
            CPU_HWP_DYN_BOOST_ON_BAT = 0;

            PLATFORM_PROFILE_ON_AC = "balanced";
            PLATFORM_PROFILE_ON_BAT = "low-power";
          }
          // chargeSettings.${cfg.chargeControl};
        };

        # Can interfere with TLP and tends to get enabled implicitly by desktop stacks.
        services.power-profiles-daemon.enable = false;
      };
    };
}
