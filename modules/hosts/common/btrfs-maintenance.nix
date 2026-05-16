{ ... }:
{
  flake.nixosModules.btrfs-maintenance =
    { lib, config, ... }:
    let
      cfg = lib.attrByPath [ "preferences" "hardware" "btrfsMaintenance" ] { enable = false; } config;
    in
    {
      config = lib.mkIf cfg.enable {
        # Weekly queued TRIM keeps SSD/LUKS discard benefits without continuous-discard write-path overhead.
        services.fstrim = {
          enable = true;
          interval = "weekly";
        };

        # Scrub verifies Btrfs checksums and repairs mirrored data where possible; monthly is low IO cost on these single-root filesystems.
        services.btrfs.autoScrub = {
          enable = true;
          interval = "monthly";
          fileSystems = [ "/" ];
        };

        # Bees dedup is useful for /nix generations but can burn IO/RAM; opt in manually per host after watching load and space savings.
        services.beesd.filesystems = lib.mkIf (cfg.dedupe.enable or false) {
          root = {
            spec = "/";
            hashTableSizeMB = cfg.dedupe.hashTableSizeMB or 1024;
            extraOptions = [
              "--loadavg-target"
              (cfg.dedupe.loadAverageTarget or "1.0")
            ];
          };
        };

        # Keep maintenance below interactive work; scrub and dedupe are throughput tasks, not latency-sensitive ones.
        systemd.services = {
          btrfs-scrub.serviceConfig = {
            Nice = 19;
            IOSchedulingClass = "idle";
          };
          "beesd@root".serviceConfig = lib.mkIf (cfg.dedupe.enable or false) {
            Nice = 19;
            IOSchedulingClass = "idle";
          };
        };
      };
    };
}
