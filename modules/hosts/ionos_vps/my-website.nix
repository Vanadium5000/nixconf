{ self, inputs, ... }:
{
  flake.nixosModules.ionos_vpsHost =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      # Turn list of keys into an attrset of { key = null; }
      keysAsAttrs =
        requiredKeys:
        builtins.listToAttrs (
          map (k: {
            name = k;
            value = null;
          }) requiredKeys
        );

      # Keep the auth password aligned with the existing services secret so
      # one rotation updates every protected dashboard consistently.
      secrets' = builtins.intersectAttrs (keysAsAttrs [
        "MY_WEBSITE_ENV"
        "SERVICES_AUTH_PASSWORD"
      ]) self.secrets;
      envText = secrets'.MY_WEBSITE_ENV;
      servicesAuthPassword = secrets'.SERVICES_AUTH_PASSWORD;
      servicesAuthGatewayPort = 41276;
      servicesAuthSigningKey = builtins.hashString "sha256" "${servicesAuthPassword}:my-website.space:services-auth-gateway";
      servicesAuthCookieName = "__Secure-services_auth";
      servicesAuthReturnCookieName = "__Secure-services_auth_return";
      servicesAuthCookieDomain = ".my-website.space";
      authGatewayBaseUrl = "http://127.0.0.1:${toString servicesAuthGatewayPort}";
      managedSubdomainsStateDir = "/var/lib/nginx-subdomains";
      managedSubdomainsSitesDir = "${managedSubdomainsStateDir}/sites";
      managedSubdomainsWebroot = "${managedSubdomainsStateDir}/acme-webroot";
      managedSubdomainsCertbotDir = "${managedSubdomainsStateDir}/certbot";
      managedSubdomainsStaticHostsFile = pkgs.writeText "nginx-managed-subdomains-static-hosts" ''
        my-website.space
        www.my-website.space
        auth.my-website.space
        dashboard.my-website.space
        netdata.my-website.space
        mitmproxy.my-website.space
        vpn.my-website.space
        cliproxyapi.my-website.space
        dokploy.my-website.space
        mongo.my-website.space
      '';
      nginxManagedSubdomains = pkgs.writeShellApplication {
        name = "nginx-managed-subdomains";
        runtimeInputs = with pkgs; [
          bash
          certbot
          coreutils
          gnugrep
          gnused
          gawk
          gum
          nginx
          systemd
        ];
        text = ''
          STATE_DIR=${lib.escapeShellArg managedSubdomainsStateDir}
          DATA_FILE=${lib.escapeShellArg "${managedSubdomainsStateDir}/subdomains.tsv"}
          SITES_DIR=${lib.escapeShellArg managedSubdomainsSitesDir}
          WEBROOT=${lib.escapeShellArg managedSubdomainsWebroot}
          CERTBOT_DIR=${lib.escapeShellArg managedSubdomainsCertbotDir}
          ACME_EMAIL=${lib.escapeShellArg config.security.acme.defaults.email}
          TRAEFIK_UPSTREAM='http://127.0.0.1:8080'
          AUTH_GATEWAY_BASE_URL=${lib.escapeShellArg authGatewayBaseUrl}
          AUTH_COOKIE_DOMAIN=${lib.escapeShellArg servicesAuthCookieDomain}
          AUTH_COOKIE_NAME=${lib.escapeShellArg servicesAuthCookieName}
          AUTH_RETURN_COOKIE_NAME=${lib.escapeShellArg servicesAuthReturnCookieName}
          STATIC_HOSTS_FILE=${lib.escapeShellArg managedSubdomainsStaticHostsFile}
        ''
        + builtins.readFile ./nginx-managed-subdomains.sh;
      };

      mkProtectedSubdomain =
        {
          port,
          extraConfig ? "",
        }:
        {
          forceSSL = true;
          enableACME = true;
          locations."= /_services-auth/check" = {
            extraConfig = ''
              internal;
              proxy_pass ${authGatewayBaseUrl}/api/check;
              proxy_pass_request_body off;
              proxy_set_header Content-Length "";
              proxy_set_header Cookie $http_cookie;
              proxy_set_header X-Forwarded-Proto https;
              proxy_set_header X-Original-Host $host;
              proxy_set_header X-Original-URI $request_uri;
            '';
          };
          locations."@services-auth-login" = {
            extraConfig = ''
              add_header Set-Cookie "${servicesAuthReturnCookieName}=$scheme://$http_host$request_uri; Domain=${servicesAuthCookieDomain}; Path=/; Max-Age=300; HttpOnly; Secure; SameSite=Lax" always;
              return 302 https://auth.my-website.space/login;
            '';
          };
          locations."/" = {
            proxyPass = "http://127.0.0.1:${toString port}/";
            proxyWebsockets = true;
            extraConfig = ''
              auth_request /_services-auth/check;
              error_page 401 = @services-auth-login;
            ''
            + extraConfig;
          };
        };
    in
    {
      imports = [
        inputs.my-website-backend.nixosModules.default
      ];

      services.services-auth-gateway = {
        enable = true;
        bindAddress = "127.0.0.1";
        port = servicesAuthGatewayPort;
        publicDomain = "my-website.space";
        cookieDomain = servicesAuthCookieDomain;
        cookieName = servicesAuthCookieName;
        returnCookieName = servicesAuthReturnCookieName;
        defaultRedirect = "https://my-website.space/";
        password = servicesAuthPassword;
        signingKey = servicesAuthSigningKey;
      };

      # Enable backend service
      services.my-website-backend = {
        enable = true;
        port = 41273; # Changed from 3000 to avoid conflicts & randomise
        envFile = pkgs.writeText ".env" envText;
      };

      # Run mongo-express in a container (isolated & easy)
      virtualisation.oci-containers.containers.mongo-express = {
        autoStart = true;
        image = "mongo-express:latest";
        ports = [ "127.0.0.1:41275:8081" ]; # Changed from 8081:8081
        environment = {
          # These are used AFTER the initial health-check
          ME_CONFIG_MONGODB_SERVER = "127.0.0.1";
          ME_CONFIG_MONGODB_PORT = "27017";
          ME_CONFIG_MONGODB_ENABLE_ADMIN = "true";
          ME_CONFIG_MONGODB_AUTH_DATABASE = "admin";
          # The outer nginx auth_request flow now owns browser auth so one
          # login covers mongo-express together with the other dashboards.
          ME_CONFIG_BASICAUTH = "false";

          # This overrides the hard-coded "mongo" host.
          ME_CONFIG_MONGODB_URL = "mongodb://127.0.0.1:27017/?authSource=admin";
        };
        # Removed --network=host to properly use port mapping and isolate
      };

      # Nginx setup
      services.nginx = {
        enable = true;
        recommendedGzipSettings = true;
        recommendedOptimisation = true;
        recommendedProxySettings = true;
        recommendedTlsSettings = true;
        appendHttpConfig = ''
          # Load additive runtime-managed subdomains after the declarative vhosts.
          # The manager rejects collisions with the static hosts defined here.
          include ${managedSubdomainsSitesDir}/*.conf;
        '';

        virtualHosts."my-website.space" = {
          serverAliases = [ "www.my-website.space" ];
          forceSSL = true; # Redirect HTTP to HTTPS
          enableACME = true; # Auto Let's Encrypt

          # Serve frontend static files
          root = "${inputs.my-website-frontend.packages.${pkgs.stdenv.hostPlatform.system}.default}";

          # Proxy backend for drfrost-solver (adjust path if needed)
          locations."/backend/drfrost-solver/" = {
            proxyPass = "http://127.0.0.1:41274/";
            proxyWebsockets = true; # If needed for WS
          };

          # Proxy backend (adjust path if needed)
          locations."/backend/" = {
            proxyPass = "http://127.0.0.1:41273/";
            proxyWebsockets = true; # If needed for WS
          };

          # Keep the existing backend auth API path stable for the site app.
          locations."/auth/api/" = {
            proxyPass = "http://127.0.0.1:41273"; # No trailing / to preserve path
            proxyWebsockets = true;
          };

          # Optional: SPA fallback for frontend routes
          locations."/" = {
            tryFiles = "$uri $uri/ /index.html";
          };
        };

        virtualHosts."auth.my-website.space" = {
          forceSSL = true;
          enableACME = true;
          locations."/" = {
            proxyPass = "${authGatewayBaseUrl}/";
            extraConfig = ''
              proxy_set_header Host $host;
              proxy_set_header X-Forwarded-Proto https;
              proxy_set_header X-Forwarded-Host $host;
            '';
          };
        };

        virtualHosts."dashboard.my-website.space" = mkProtectedSubdomain {
          port = 8082;
        };

        virtualHosts."netdata.my-website.space" = mkProtectedSubdomain {
          port = 19999;
          extraConfig = ''
            # Netdata's bundled UI should render at / instead of falling back
            # to the API metadata endpoint when exposed through nginx.
            proxy_set_header Host $host;
          '';
        };

        virtualHosts."mitmproxy.my-website.space" = mkProtectedSubdomain {
          port = 8083;
        };

        virtualHosts."vpn.my-website.space" = mkProtectedSubdomain {
          port = 10802;
        };

        virtualHosts."cliproxyapi.my-website.space" = mkProtectedSubdomain {
          port = 8317;
        };

        virtualHosts."dokploy.my-website.space" = mkProtectedSubdomain {
          # Dokploy's UI is fronted by the localhost-only Traefik container
          # because the upstream module's direct Swarm port publication hangs on
          # this host. Port 8080 is the HTTP entrypoint rebound in ionos_vps.
          port = 8080;
        };

        virtualHosts."mongo.my-website.space" = mkProtectedSubdomain {
          port = 41275;
        };
      };

      # ACME (Let's Encrypt) setup
      security.acme = {
        acceptTerms = true;
        defaults.email = "vanadium5000@gmail.com"; # Required for cert issuance
      };

      environment.systemPackages = [ nginxManagedSubdomains ];

      systemd.tmpfiles.rules = [
        "d ${managedSubdomainsStateDir} 0750 root root -"
        "d ${managedSubdomainsSitesDir} 0750 root root -"
        "d ${managedSubdomainsWebroot} 0755 root root -"
        "d ${managedSubdomainsCertbotDir} 0700 root root -"
        "d ${managedSubdomainsCertbotDir}/config 0700 root root -"
        "d ${managedSubdomainsCertbotDir}/work 0700 root root -"
        "d ${managedSubdomainsCertbotDir}/logs 0700 root root -"
        "f ${managedSubdomainsStateDir}/subdomains.tsv 0640 root root -"
        "f ${managedSubdomainsSitesDir}/_empty.conf 0644 root root -"
      ];

      systemd.services.nginx-managed-subdomains-renew = {
        description = "Renew runtime-managed nginx subdomain certificates";
        after = [
          "nginx.service"
          "network-online.target"
        ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${nginxManagedSubdomains}/bin/nginx-managed-subdomains renew-all";
        };
      };

      systemd.timers.nginx-managed-subdomains-renew = {
        description = "Daily renewal for runtime-managed nginx subdomain certificates";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "daily";
          RandomizedDelaySec = "1h";
          Persistent = true;
        };
      };

      # Persist uploaded images and ACME/SSL certificates across reboots
      # Without this, user images are lost and Let's Encrypt rate-limits hit on every reboot
      impermanence.nixos.directories = [
        {
          directory = "/var/lib/my-website-backend";
          user = "my-website-backend";
          group = "my-website-backend";
          mode = "0750";
        }
        {
          directory = "/var/lib/acme";
          user = "acme";
          group = "acme";
          mode = "0750";
        }
        {
          # Managed app subdomains are runtime-created, so their nginx snippets,
          # ACME webroot, and certbot state must survive the impermanent root.
          directory = managedSubdomainsStateDir;
          user = "root";
          group = "root";
          mode = "0750";
        }
      ];

      # Open firewall for HTTP/HTTPS
      networking.firewall.allowedTCPPorts = [
        80
        443
      ];
    };
}
