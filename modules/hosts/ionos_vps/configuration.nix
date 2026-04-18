{ self, inputs, ... }:
{
  flake.nixosConfigurations.ionos_vps = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      self.nixosModules.ionos_vpsHost
    ];
  };

  flake.nixosModules.ionos_vpsHost =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    {
      imports = [
        self.nixosModules.terminal
        inputs.nix-dokploy.nixosModules.default

        # Disko
        inputs.disko.nixosModules.disko
        self.diskoConfigurations.ionos_vps
      ];

      # Enable SSH support
      users.users.${config.preferences.user.username}.openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFsIUmSPfK9/ncfGjINjeI7sz+QK7wyaYJZtLhVpiU66 thealfiecrawford@icloud.com"
      ];

      # Use terminal-friendly curses backend
      programs.gnupg.agent.pinentryPackage = lib.mkForce pkgs.pinentry-curses;

      # Disable git-sync for passwords, I don't want any important credentials on the system
      services.git-sync.enable = lib.mkForce false;

      # Dokploy depends on a real Docker daemon for Swarm orchestration.
      # Podman's CLI-compat layer is useful elsewhere in the repo, but Dokploy needs
      # the Docker service semantics instead of only a socket-compatible alias.
      virtualisation.docker = {
        enable = true;
        daemon.settings.live-restore = false;
      };
      virtualisation.podman.dockerCompat = lib.mkForce false;

      services.dokploy = {
        enable = true;
        # Keep Dokploy private and let nginx remain the only public edge.
        port = "127.0.0.1:3000:3000";
        # Reuse the shared services password as deterministic seed material so the
        # DB password survives rebuilds without adding another manual bootstrap secret.
  database.passwordFile = "${pkgs.writeText "dokploy-db-password" (
    builtins.hashString "sha256" "${self.secrets.SERVICES_AUTH_PASSWORD}:dokploy-db"
  )}";
      };

      services.cliproxyapi = {
        enable = true;
        host = "127.0.0.1"; # Secure: bind localhost only
        openFirewall = false; # Secure: close public port
      };

      services.vpn-proxy = {
        enable = true;
        bindAddress = "127.0.0.1"; # Secure: bind localhost only
      };
      services.unison-sync.enable = true;

      # System monitoring — real-time metrics with persistent history
      services.netdata-monitor.enable = true;
      preferences.allowedUnfree = [ "netdata" ];

      # Fleet dashboard portal — accessible via Tailscale at http://ionos-vps:8082
      services.homepage-monitor.enable = true;

      # HTTPS traffic analyzer — on-demand: systemctl start mitmproxy
      services.mitmproxy.enable = true;
      services.mitmproxy.trustCA = true;

      # Dokploy stores Docker images, volumes, and swarm state under /var/lib/docker.
      # Persisting it avoids wiping deployments every reboot on an impermanent-root host.
      impermanence.nixos.cache.directories = [ "/var/lib/docker" ];

      # Preferences
      preferences = {
        hostName = "ionos_vps";
        profiles = {
          terminal.enable = true;
          server.enable = true;
        };
        user = {
          username = "main";
        };
        git = {
          username = "Vanadium5000";
          email = "vanadium5000@gmail.com";
        };
      };

      # No cuda - doesn't have an Nvidia GPU
      nixpkgs.config.cudaSupport = false;

      # State version
      system.stateVersion = "25.11";
    };
}
