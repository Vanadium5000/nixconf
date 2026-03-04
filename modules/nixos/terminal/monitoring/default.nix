# Monitoring module aggregator
# Extends the terminal module to include all monitoring sub-modules.
# Each sub-module is independently toggleable (all disabled by default).
{ self, ... }:
{
  flake.nixosModules.terminal =
    { ... }:
    {
      imports = [
        self.nixosModules.netdata-monitor
        self.nixosModules.homepage-monitor
        self.nixosModules.mitmproxy
      ];
    };
}
