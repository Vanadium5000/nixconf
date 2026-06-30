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
        self.nixosModules.cockpit
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

      # Dokploy depends on the shared real Docker daemon for Swarm orchestration.

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

        auth.secretFile = "${pkgs.writeText "dokploy-auth-secret" self.secrets.DOKPLOY_AUTH_SECRET}";
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
        # CPA Usage Keeper authenticates to CLIProxyAPI management endpoints;
        # inject the same secret into CPA so stale mutable config.yaml hashes
        # cannot make keeper fall back to the removed legacy export route.
        # Source: https://github.com/router-for-me/CLIProxyAPI/blob/v6.10.1/internal/api/handlers/management/handler.go
        managementKey = self.secrets.CLIPROXYAPI_KEY;
        openFirewall = false; # Secure: close public port
      };

      services.omniroute = {
        enable = true;
        host = "127.0.0.1"; # Traefik terminates TLS and is the only public listener.
        # OmniRoute defaults to port 20128 for both dashboard and /v1 API.
        # Source: https://github.com/diegosouzapw/OmniRoute/blob/v3.7.9/docs/ENVIRONMENT.md
        port = 20128;
        # Keep the bootstrap password in persisted runtime state instead of
        # interpolating self.secrets into the generated systemd unit/Nix store.
        # Source: modules/nixos/terminal/omniroute.nix initialPasswordFile.
        initialPasswordFile = "/var/lib/omniroute/initial-password";
        openFirewall = false; # Traefik is the only public entrypoint.
      };

      services.bifrost = {
        enable = true;
        host = "127.0.0.1"; # Traefik terminates TLS and is the only public listener.
        # 8080 is already CPA Usage Keeper; keep Bifrost adjacent to OmniRoute's
        # AI gateway port while avoiding public listeners. Source: upstream Bifrost
        # module exposes explicit host/port flags for bifrost-http.
        port = 20129;
        openFirewall = false;
        environment = {
          BIFROST_API_KEY = self.secrets.BIFROST_API_KEY or "";
          BIFROST_ENCRYPTION_KEY = self.secrets.BIFROST_ENCRYPTION_KEY or "";
          CLIPROXYAPI_KEY = self.secrets.CLIPROXYAPI_KEY;
        };
        settings = {
          "$schema" = "https://www.getbifrost.ai/schema";
          encryption_key = "env.BIFROST_ENCRYPTION_KEY";
          client = {
            enable_logging = true;
            enforce_auth_on_inference = true;
          };
          providers.openai = {
            keys = [
              {
                name = "cliproxyapi";
                value = "env.CLIPROXYAPI_KEY";
                # Let CLIProxyAPI's OpenAI-compatible /v1/models endpoint own
                # model discovery instead of pinning a stale gateway model list.
                # Source: Bifrost config schema `models: [\"*\"]` allows all.
                models = [ "*" ];
                weight = 1.0;
              }
            ];
            network_config = {
              base_url = "http://127.0.0.1:8317";
              default_request_timeout_in_seconds = 200;
            };
            custom_provider_config = {
              base_provider_type = "openai";
              allowed_requests = {
                list_models = true;
                text_completion = false;
                text_completion_stream = false;
                chat_completion = true;
                chat_completion_stream = true;
                responses = false;
                responses_stream = false;
                embedding = false;
                speech = false;
                speech_stream = false;
                transcription = false;
                transcription_stream = false;
              };
              request_path_overrides = {
                list_models = "/v1/models";
                chat_completion = "/v1/chat/completions";
                chat_completion_stream = "/v1/chat/completions";
              };
            };
          };
          governance.virtual_keys = [
            {
              id = "router";
              name = "Router";
              value = "env.BIFROST_API_KEY";
              description = "Default Router key for OpenAI-compatible Bifrost clients";
              is_active = true;
              provider_configs = [
                {
                  provider = "openai";
                  weight = 1.0;
                  allowed_models = [ "*" ];
                  key_ids = [ "*" ];
                }
              ];
            }
          ];
          config_store = {
            enabled = true;
            type = "sqlite";
            config.path = "./config.db";
          };
          logs_store = {
            enabled = true;
            type = "sqlite";
            config.path = "./logs.db";
          };
        };
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
        # CLIProxyAPI v6.10.x no longer exposes the legacy usage export route;
        # cpa-usage-keeper v1.3.2 can instead read the management RESP queue on
        # the same 8317 listener derived from cpaBaseUrl.
        # Sources: https://github.com/router-for-me/CLIProxyAPI/tree/v6.10.1
        # https://github.com/Willxup/cpa-usage-keeper/blob/v1.3.2/.env.example
        usageSyncMode = "redis";
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

      # Fleet dashboard portal — accessible via Tailscale at http://main-vps:8082
      services.homepage-monitor.enable = true;

      # ntfy keeps runtime databases below /var/lib; persist it explicitly
      # because this host wipes the root filesystem on boot. Bifrost's state is
      # owned by systemd StateDirectory and intentionally not bind-mounted here:
      # a stale public /var/lib/bifrost mount made DynamicUser fail at
      # status=238/STATE_DIRECTORY before the service could start.
      impermanence.nixos.directories = [
        "/var/lib/ntfy-sh"
      ];

      # Preferences
      preferences = {
        hostName = "main_vps";
        configFiles.source = "store"; # main_vps has no ~/nixconf checkout; install repo-owned configs from the flake store copy.
        profiles = {
          terminal.enable = true;
          server.enable = true;
        };
        hardware.memory.enable = true;
        hardware.btrfsMaintenance.enable = true;
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
