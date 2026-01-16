{ ... }:
{
  flake.nixosModules.tailscale =
    { config, ... }:
    {
      services.tailscale.enable = true;

      networking.firewall.trustedInterfaces = [ "tailscale0" ];
      networking.firewall.allowedUDPPorts = [ config.services.tailscale.port ];

      # Persist Tailscale state (sessions/connections) across reboots
      impermanence.nixos.cache.directories = [ "/var/lib/tailscale" ];
    };
}
