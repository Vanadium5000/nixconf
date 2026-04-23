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
        # Disable Dokploy's direct UI publication because this nix-dokploy
        # revision can only expose it through Swarm's ingress mesh, which hangs
        # on this host. The public Traefik edge instead proxies to the
        # localhost-bound Traefik container started below.
        port = null;
        traefik.dynamicConfig.dokploy-ui = {
          http = {
            routers.dokploy-ui = {
              rule = "Host(`dokploy.my-website.space`)";
              entryPoints = [ "web" ];
              service = "dokploy-ui";
            };
            services.dokploy-ui.loadBalancer.servers = [
              {
                url = "http://dokploy-app:3000";
              }
            ];
          };
        };
        # Reuse the shared services password as deterministic seed material so the
        # DB password survives rebuilds without adding another manual bootstrap secret.
        database.passwordFile = "${pkgs.writeText "dokploy-db-password" (
          builtins.hashString "sha256" "${self.secrets.SERVICES_AUTH_PASSWORD}:dokploy-db"
        )}";
      };

      systemd.services.dokploy-traefik.serviceConfig.ExecStart = lib.mkForce (
        let
          # nix-dokploy hard-codes host ports 80/443 in
          # nix-dokploy.nix (rev 19f9efec3c106e979b1d8fef083c86d73e6ff7ef), which
          # collides with this host's Traefik edge design. Rebinding Traefik to
          # localhost-only one-above-edge ports keeps Dokploy's internal proxy
          # available without stealing the public ACME listeners.
          dokployTraefikStart = pkgs.writeShellApplication {
            name = "dokploy-traefik-start-localhost";
            runtimeInputs = [ pkgs.docker ];
            text = ''
              echo "Waiting for Dokploy to generate Traefik configuration..."
              timeout=120
              while [ ! -f "/var/lib/dokploy/traefik/traefik.yml" ]; do
                sleep 1
                timeout=$((timeout - 1))
                if [ "$timeout" -le 0 ]; then
                  echo "Error: Timed out waiting for traefik.yml"
                  exit 1
                fi
              done
              echo "Traefik configuration found."

              if docker ps -a --format '{{.Names}}' | grep -q '^dokploy-traefik$'; then
                echo "Starting existing Traefik container..."
                docker start dokploy-traefik
              else
                echo "Creating and starting Traefik container..."
                docker run -d \
                  --name dokploy-traefik \
                  --network dokploy-network \
                  --restart=always \
                  -v /var/run/docker.sock:/var/run/docker.sock \
                  -v /var/lib/dokploy/traefik/traefik.yml:/etc/traefik/traefik.yml \
                  -v /var/lib/dokploy/traefik/dynamic:/etc/dokploy/traefik/dynamic \
                  -p 127.0.0.1:81:80/tcp \
                  -p 127.0.0.1:444:443/tcp \
                  -p 127.0.0.1:444:443/udp \
                  traefik:v3.6.13
              fi
            '';
          };
        in
        "${dokployTraefikStart}/bin/dokploy-traefik-start-localhost"
      );

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
      # Dokploy's localhost-bound Traefik already occupies 127.0.0.1:81 on this host.
      # Move mitmproxy's explicit proxy listener so the on-demand analyzer can start reliably.
      services.mitmproxy.proxyPort = 8084;
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
