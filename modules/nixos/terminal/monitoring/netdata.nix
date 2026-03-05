# Netdata — real-time system monitoring dashboard
# Provides per-second metrics for CPU, RAM, disk, network, containers, and systemd services.
# Binds to localhost by default — Tailscale's trustedInterfaces handles fleet access.
#
# For laptops with ephemeral root, use RAM mode (stateless):
#   services.netdata-monitor.enable = true;
#   services.netdata-monitor.memoryMode = "ram";
#   services.netdata-monitor.updateEvery = 5;  # longer interval saves battery
#
# For servers with persistent storage, use dbengine mode (historical data):
#   services.netdata-monitor.enable = true;
#   services.netdata-monitor.memoryMode = "dbengine";
{ ... }:
{
  flake.nixosModules.netdata-monitor =
    {
      config,
      lib,
      ...
    }:
    let
      inherit (lib)
        mkEnableOption
        mkOption
        mkIf
        mkMerge
        types
        ;
      cfg = config.services.netdata-monitor;
    in
    {
      options.services.netdata-monitor = {
        enable = mkEnableOption "Netdata real-time system monitoring";

        bindAddress = mkOption {
          type = types.str;
          default = "127.0.0.1";
          description = ''
            Address to bind Netdata's web interface.
            Defaults to localhost — Tailscale's trustedInterfaces already
            allows fleet access without exposing metrics to the public internet.
          '';
        };

        memoryMode = mkOption {
          type = types.enum [
            "ram"
            "dbengine"
          ];
          default = "dbengine";
          description = ''
            How Netdata stores collected metrics.
            - "ram": metrics only in memory, lost on reboot (ideal for laptops)
            - "dbengine": persistent time-series DB on disk (ideal for servers)
          '';
        };

        updateEvery = mkOption {
          type = types.ints.positive;
          default = 2;
          description = ''
            Seconds between metric collections.
            Lower = more detail but more CPU/battery.
            2s is a good balance; 5s recommended for laptops on battery.
          '';
        };
      };

      config = mkIf cfg.enable {
        services.netdata = {
          enable = true;

          config = {
            global = {
              "memory mode" = cfg.memoryMode;
              "update every" = toString cfg.updateEvery;
            };

            web = {
              "bind to" = cfg.bindAddress;
            };

            # Reduce disk writes for dbengine — tier data over time
            # Tier 0: per-second, 14 days retention
            # Tier 1: per-minute, 3 months retention
            # Tier 2: per-hour, 2 years retention
            db = mkIf (cfg.memoryMode == "dbengine") {
              "dbengine tier backfill" = "new";
            };

            # Explicitly disable plugins that cause log spam on systems without the required hardware/software
            plugins = {
              "freeipmi" = "no"; # Only useful on bare-metal enterprise servers with IPMI
              "tc" = "no"; # Only useful if using FireQOS for traffic shaping
              "charts.d" = "no"; # Legacy bash plugins (causes opensipsctl errors)
              "python.d" = "no"; # Legacy python plugins (causes MissingModule errors, mostly replaced by go.d)
            };
          };
        };

        # Persist Netdata data only when using dbengine (historical metrics matter)
        # RAM mode is fully stateless — nothing to persist
        impermanence = mkMerge [
          (mkIf (cfg.memoryMode == "dbengine") {
            nixos.directories = [
              {
                directory = "/var/lib/netdata";
                user = "netdata";
                group = "netdata";
                mode = "0750";
              }
            ];
            nixos.cache.directories = [ "/var/cache/netdata" ];
          })
        ];
      };
    };
}
