{ self, inputs, ... }:
{
  flake.nixosConfigurations.main_vps = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      self.nixosModules.main_vpsHost
    ];
  };

  flake.nixosModules.main_vpsHost =
    {
      config,
      pkgs,
      lib,
      publicBaseDomain,
      ...
    }:
    {
      _module.args.publicBaseDomain = self.secrets.PUBLIC_BASE_DOMAIN;

      imports = [
        self.nixosModules.terminal
        inputs.nix-dokploy.nixosModules.default

        # Disko
        inputs.disko.nixosModules.disko
        self.diskoConfigurations.main_vps
      ];

      # Enable SSH support
      users.users.${config.preferences.user.username}.openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFsIUmSPfK9/ncfGjINjeI7sz+QK7wyaYJZtLhVpiU66 ssh-admin@main-vps"
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
        image = "dokploy/dokploy:v0.29.2"; # USE NEWER & BETTER IMAGE
        environment = {
          # Dokploy's auth layer validates the browser Origin header against a
          # trusted-origin list. Once TLS terminates at the host Traefik edge,
          # logins originate from the public subdomain instead of localhost, so
          # the public URL must be trusted explicitly to avoid INVALID_ORIGIN.
          BETTER_AUTH_TRUSTED_ORIGINS = "https://${publicBaseDomain},https://www.${publicBaseDomain},https://dokploy.${publicBaseDomain},http://localhost:3000";
        };
        traefik.dynamicConfig.dokploy-ui = {
          http = {
            routers.dokploy-ui = {
              rule = "Host(`dokploy.${publicBaseDomain}`)";
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

      services.cpa-usage-keeper = {
        enable = true;
        openFirewall = false; # Traefik is the only public entrypoint for this dashboard.
        # Upstream v1.3.2 derives app.db, logs/, and backups/ from WORK_DIR, so
        # keep the NixOS state path stable across impermanent-root boots.
        # Source: https://github.com/Willxup/cpa-usage-keeper/releases/tag/v1.3.2
        workDir = "/var/lib/cpa-usage-keeper";
        cpaBaseUrl = "http://127.0.0.1:8317";
        # cpa-usage-keeper calls CLIProxyAPI management endpoints, so reuse the
        # same management secret instead of maintaining a second equivalent key.
        cpaManagementKey = self.secrets.CLIPROXYAPI_KEY;
        # Existing shared Traefik auth protects the public subdomain, avoiding a
        # second in-app login whose sessions are lost on service restart.
        # Source: https://github.com/Willxup/cpa-usage-keeper/blob/v1.3.2/README.md
        authEnabled = false;
      };

      services.vpn-proxy = {
        enable = true;
        bindAddress = "127.0.0.1"; # Secure: bind localhost only
      };
      services.ntfy-sh = {
        enable = true;
        settings = {
          # Bind on all interfaces so the service is reachable over Tailscale.
          # The normal firewall stays closed; tailscale0 is already trusted separately.
          listen-http = "0.0.0.0:2586";

          # Required by ntfy for attachment download links on self-hosted instances.
          # Tailscale DNS keeps the URL stable across host IP changes.
          base-url = "http://main-vps:2586";
          upstream-base-url = "https://ntfy.sh";

          # Keep attachments simple and enabled without introducing auth or extra proxying.
          attachment-cache-dir = "/var/lib/ntfy-sh/attachments";
        };
      };
      systemd.services.ntfy-sh.serviceConfig.DynamicUser = lib.mkForce false;
      services.unison-sync.enable = true;

      # System monitoring — real-time metrics with persistent history
      services.netdata-monitor.enable = true;
      preferences.allowedUnfree = [ "netdata" ];

      # Fleet dashboard portal — accessible via Tailscale at http://main-vps:8082
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

      # ntfy keeps its cache, auth DB, and attachments in /var/lib/ntfy-sh.
      # Use a normal persistent state path to avoid DynamicUser StateDirectory clashes.
      impermanence.nixos.directories = [ "/var/lib/ntfy-sh" ];

      # Preferences
      preferences = {
        hostName = "main_vps";
        profiles = {
          terminal.enable = true;
          server.enable = true;
        };
        user = {
          username = "main";
        };
      };

      # No cuda - doesn't have an Nvidia GPU
      nixpkgs.config.cudaSupport = false;

      # State version
      system.stateVersion = "25.11";
    };
}
