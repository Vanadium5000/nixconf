{ ... }:
{
  flake.nixosModules.tailscale =
    { config, ... }:
    {
      services.tailscale.enable = true;

      # NOTE: All ports are accessible by default via Tailscale from other connected devices
      networking.firewall.trustedInterfaces = [ "tailscale0" ];
      networking.firewall.allowedUDPPorts = [ config.services.tailscale.port ];

      # Persist Tailscale state (sessions/connections) across reboots
      impermanence.nixos.cache.directories = [ "/var/lib/tailscale" ];
    };
}
