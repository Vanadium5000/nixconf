{
  flake.nixosModules.tlp = {
    # Power management (increased battery-life on laptops)
    services.tlp = {
      enable = true;
      settings = {
        # Disables bluetooth on startup
        #DEVICES_TO_DISABLE_ON_STARTUP = "bluetooth";

        # The processor selects the operating frequencies autonomously
        # within the limits imposed by the hardware, including turbo boost.
        # The powersave governor can also lead to max frequency
        CPU_DRIVER_OPMODE_ON_AC = "active";
        CPU_DRIVER_OPMODE_ON_BAT = "active";

        # Selects the CPU scaling governor for automatic frequency scaling
        CPU_SCALING_GOVERNOR_ON_AC = "powersave"; # default
        CPU_SCALING_GOVERNOR_ON_BAT = "powersave"; # default

        # Change CPU energy/performance policy to power (default is balance_power)
        CPU_ENERGY_PERF_POLICY_ON_AC = "balance_performance"; # default
        CPU_ENERGY_PERF_POLICY_ON_BAT = "power"; # more power-efficient than default

        # Limit power consumption under high CPU load
        #CPU_MIN_PERF_ON_AC = 0; # default
        #CPU_MAX_PERF_ON_AC = 100; # default
        #CPU_MIN_PERF_ON_BAT = 0; # default
        #CPU_MAX_PERF_ON_BAT = 20; # more power-efficient than default

        # Disable turbo boost on battery
        CPU_BOOST_ON_AC = 1; # default
        CPU_BOOST_ON_BAT = 0; # default

        CPU_HWP_DYN_BOOST_ON_AC = 1; # default
        CPU_HWP_DYN_BOOST_ON_BAT = 0; # default

        # Enable the platform profile low-power
        PLATFORM_PROFILE_ON_AC = "balanced"; # default
        PLATFORM_PROFILE_ON_BAT = "low-power"; # default

        # Battery conservation mode
        START_CHARGE_THRESH_BAT0 = 60; # battery charge level below which charging will begin when connecting the charger
        #STOP_CHARGE_THRESH_BAT0 = 70; # battery charge level above which charging will stop while the charger is connected
        STOP_CHARGE_THRESH_BAT0 = 1; # batteries charge to the fixed threshold
      };
    };

    # Can interfere with tlp, often enabled by DEs
    services.power-profiles-daemon.enable = false;
  };
}
