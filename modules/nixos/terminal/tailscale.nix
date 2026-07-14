{ self, ... }:
{
  flake.nixosModules.tailscale =
    { config, lib, ... }:
    let
      tailscaled = "${config.services.tailscale.package}/bin/.tailscaled-wrapped";
    in
    {
      services.tailscale.enable = true;

      services.opensnitch.mutableRules = lib.mkIf config.services.opensnitch.enable {
        "020-allow-tailscaled" = {
          created = "2026-07-09T00:00:00Z";
          updated = "2026-07-09T00:00:00Z";
          name = "020-allow-tailscaled";
          description = "Allow the configured Tailscale daemon package; DERP, NAT traversal, and control-plane endpoints are intentionally dynamic.";
          action = "allow";
          duration = "always";
          enabled = true;
          precedence = true;
          nolog = false;
          operator = {
            type = "simple";
            operand = "process.path";
            data = tailscaled;
            sensitive = false;
            list = null;
          };
        };
      };

      # NOTE: All ports are accessible by default via Tailscale from other connected devices
      networking.firewall.trustedInterfaces = [ "tailscale0" ];
      networking.firewall.allowedUDPPorts = [ config.services.tailscale.port ];

      # Persist Tailscale state (sessions/connections) across reboots
      impermanence.nixos.cache.directories = [ "/var/lib/tailscale" ];
    };
}
