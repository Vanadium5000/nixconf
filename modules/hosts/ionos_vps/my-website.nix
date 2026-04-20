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

      # Pull the wildcard ACME key and the shared dashboard password from the
      # same generated secrets surface so nginx/auth changes stay declarative.
      secrets' = builtins.intersectAttrs (keysAsAttrs [
        "IONOS_API_KEY"
        "MY_WEBSITE_ENV"
        "SERVICES_AUTH_PASSWORD"
      ]) self.secrets;
      envText = secrets'.MY_WEBSITE_ENV;
      ionosApiKey = secrets'.IONOS_API_KEY;
      servicesAuthPassword = secrets'.SERVICES_AUTH_PASSWORD;
      servicesAuthGatewayPort = 41276;
      servicesAuthSigningKey = builtins.hashString "sha256" "${servicesAuthPassword}:my-website.space:services-auth-gateway";
      servicesAuthCookieName = "__Secure-services_auth";
      servicesAuthReturnCookieName = "__Secure-services_auth_return";
      servicesAuthCookieDomain = ".my-website.space";
      authGatewayBaseUrl = "http://127.0.0.1:${toString servicesAuthGatewayPort}";
      traefikUpstream = "http://127.0.0.1:81";
      # Keep the ACME host key filesystem-safe so nginx and the ACME module
      # agree on the certificate directory for wildcard consumers.
      wildcardAcmeHost = "my-website-space-wildcard";
      wildcardUnauthenticatedHosts = [ ];
      servicesAuthCookieStripPattern = "(^|;[[:space:]]*)(${servicesAuthCookieName}|${servicesAuthReturnCookieName})=[^;]*";
      # lego reads `IONOS_API_KEY_FILE` as a path whose contents are the raw API
      # key, so this file must contain only the secret value rather than `KEY=`.
      ionosAcmeCredentialsFile = pkgs.writeText "ionos-acme-api-key" ionosApiKey;
      servicesAuthLocations = {
        "= /_services-auth/check" = {
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
        "@services-auth-login" = {
          extraConfig = ''
            add_header Set-Cookie "${servicesAuthReturnCookieName}=$scheme://$http_host$request_uri; Domain=${servicesAuthCookieDomain}; Path=/; Max-Age=300; HttpOnly; Secure; SameSite=Lax" always;
            return 302 https://auth.my-website.space/login;
          '';
        };
      };
      mkTraefikForwardedSubdomain =
        {
          authenticated ? true,
          extraConfig ? "",
        }:
        {
          forceSSL = true;
          useACMEHost = wildcardAcmeHost;
          locations = (lib.optionalAttrs authenticated servicesAuthLocations) // {
            "/" = {
              proxyPass = "${traefikUpstream}/";
              proxyWebsockets = true;
              extraConfig = ''
                 # Preserve the browser-facing host and forwarding chain so
                 # Traefik routes wildcard traffic exactly like the old runtime
                 # nginx snippets instead of collapsing everything into one host.
                 proxy_set_header Host $host;
                 proxy_set_header X-Real-IP $remote_addr;
                proxy_set_header X-Forwarded-Proto https;
                proxy_set_header X-Forwarded-Host $host;
                proxy_set_header X-Forwarded-Port 443;
                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              ''
              + lib.optionalString authenticated ''
                auth_request /_services-auth/check;
                error_page 401 = @services-auth-login;
                # The shared edge auth cookie is only for nginx's gate. Strip it
                # from the upstream request so Traefik-backed apps see the same
                # effective cookies they would receive without the edge wrapper.
                set $sanitized_cookie $http_cookie;
                if ($sanitized_cookie ~ "${servicesAuthCookieStripPattern}") {
                  set $sanitized_cookie $1$2;
                }
                if ($sanitized_cookie ~ "^;[[:space:]]*(.*)$") {
                  set $sanitized_cookie $1;
                }
                proxy_set_header Cookie $sanitized_cookie;
              ''
              + extraConfig;
            };
          };
        };
      mkProtectedSubdomain =
        {
          port,
          extraConfig ? "",
        }:
        {
          forceSSL = true;
          useACMEHost = wildcardAcmeHost;
          locations = servicesAuthLocations // {
            "/" = {
              proxyPass = "http://127.0.0.1:${toString port}/";
              proxyWebsockets = true;
              extraConfig = ''
                auth_request /_services-auth/check;
                error_page 401 = @services-auth-login;
              ''
              + extraConfig;
            };
          };
        };
      wildcardUnauthenticatedVhosts = builtins.listToAttrs (
        map (hostname: {
          name = hostname;
          value = mkTraefikForwardedSubdomain {
            authenticated = false;
          };
        }) wildcardUnauthenticatedHosts
      );
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
        virtualHosts = {
          "my-website.space" = {
            serverAliases = [ "www.my-website.space" ];
            forceSSL = true; # Redirect HTTP to HTTPS
            enableACME = true; # HTTP-01 remains sufficient for the apex site

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

          "auth.my-website.space" = {
            forceSSL = true;
            useACMEHost = wildcardAcmeHost;
            locations."/" = {
              proxyPass = "${authGatewayBaseUrl}/";
              extraConfig = ''
                proxy_set_header Host $host;
                proxy_set_header X-Forwarded-Proto https;
                proxy_set_header X-Forwarded-Host $host;
              '';
            };
          };

          "openclaw.my-website.space" = mkTraefikForwardedSubdomain {
            authenticated = false;
          };

          "dashboard.my-website.space" = mkProtectedSubdomain {
            port = 8082;
          };

          "netdata.my-website.space" = mkProtectedSubdomain {
            port = 19999;
            extraConfig = ''
              # Netdata's bundled UI should render at / instead of falling back
              # to the API metadata endpoint when exposed through nginx.
              proxy_set_header Host $host;
            '';
          };

          "mitmproxy.my-website.space" = mkProtectedSubdomain {
            port = 8083;
          };

          "vpn.my-website.space" = mkProtectedSubdomain {
            port = 10802;
          };

          "cliproxyapi.my-website.space" = mkProtectedSubdomain {
            port = 8317;
          };

          "dokploy.my-website.space" = mkProtectedSubdomain {
            # Dokploy's UI is fronted by the localhost-only Traefik container
            # because the upstream module's direct Swarm port publication hangs on
            # this host. Port 81 is the HTTP entrypoint rebound in ionos_vps.
            port = 81;
          };

          "mongo.my-website.space" = mkProtectedSubdomain {
            port = 41275;
          };

          "*.my-website.space" = mkTraefikForwardedSubdomain { };
        }
        // wildcardUnauthenticatedVhosts;
      };

      # ACME (Let's Encrypt) setup
      security.acme = {
        acceptTerms = true;
        defaults.email = "vanadium5000@gmail.com"; # Required for cert issuance
        certs.${wildcardAcmeHost} = {
          domain = "*.my-website.space";
          dnsProvider = "ionos";
          # Wildcard certs require DNS-01 because HTTP-01 cannot prove control
          # of arbitrary future subdomains before nginx has a matching vhost.
          credentialFiles = {
            IONOS_API_KEY_FILE = ionosAcmeCredentialsFile;
          };
          group = config.services.nginx.group;
          reloadServices = [ "nginx.service" ];
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
      ];

      # Open firewall for HTTP/HTTPS
      networking.firewall.allowedTCPPorts = [
        80
        443
      ];
    };
}
