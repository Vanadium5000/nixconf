{ ... }:
{
  flake.nixosModules.memory =
    { lib, config, ... }:
    let
      cfg = lib.attrByPath [ "preferences" "hardware" "memory" ] { enable = false; } config;
    in
    {
      config = lib.mkIf cfg.enable {
        # Compressed RAM swap absorbs transient browser/build spikes before disk swap; Garuda uses 90%, 50% is a safer default on mixed desktop/server hosts.
        zramSwap = {
          enable = true;
          algorithm = "zstd";
          memoryPercent = 50;
          priority = 100;
        };

        # Prefer swapping to cheap zram and do not read clustered swap pages; this is the low-risk subset of Garuda/CachyOS memory sysctls.
        boot.kernel.sysctl = {
          "vm.swappiness" = 100;
          "vm.page-cluster" = 0;
        };

        # Keep oomd proactive but predictable: nix builds are restartable, user sessions are disruptive to kill.
        systemd.oomd = {
          enable = true;
          enableRootSlice = true;
          enableSystemSlice = true;
          enableUserSlices = true;
          settings.OOM = {
            SwapUsedLimit = "90%";
            DefaultMemoryPressureDurationSec = "20s";
          };
        };

        # Build failures are preferable to a wedged machine; killing nix-daemon children frees memory quickly under pressure.
        systemd.services.nix-daemon.serviceConfig = {
          ManagedOOMMemoryPressure = "kill";
          ManagedOOMMemoryPressureLimit = "50%";
        };

        # Preserve the interactive desktop/session when oomd has less disruptive victims available.
        systemd.slices.user.sliceConfig.ManagedOOMPreference = "avoid";
      };
    };
}
