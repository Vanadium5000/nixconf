{ self, ... }:
{
  flake.nixosModules.main_vpsHost =
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
      # same generated secrets surface so proxy/auth changes stay declarative.
      secrets' = builtins.intersectAttrs (keysAsAttrs [
        "IONOS_API_KEY"
        "PUBLIC_BASE_DOMAIN"
        "SERVICES_AUTH_PASSWORD"
      ]) self.secrets;
      ionosApiKey = secrets'.IONOS_API_KEY;
      publicBaseDomain = secrets'.PUBLIC_BASE_DOMAIN;
      servicesAuthPassword = secrets'.SERVICES_AUTH_PASSWORD;
      servicesAuthGatewayPort = 41276;
      mkHostname =
        subdomain: if subdomain == null then publicBaseDomain else "${subdomain}.${publicBaseDomain}";
      apexDomain = mkHostname null;
      wwwDomain = mkHostname "www";
      authDomain = mkHostname "auth";
      openclawDomain = mkHostname "openclaw";
      dashboardDomain = mkHostname "dashboard";
      netdataDomain = mkHostname "netdata";
      mitmproxyDomain = mkHostname "mitmproxy";
      vpnDomain = mkHostname "vpn";
      cliproxyapiDomain = mkHostname "cliproxyapi";
      dokployDomain = mkHostname "dokploy";
      mongoDomain = mkHostname "mongo";
      wildcardDomainPattern = lib.replaceStrings [ "." ] [ "\\." ] publicBaseDomain;
      servicesAuthSigningKey = builtins.hashString "sha256" "${servicesAuthPassword}:${publicBaseDomain}:services-auth-gateway";
      servicesAuthCookieName = "__Secure-services_auth";
      servicesAuthReturnCookieName = "__Secure-services_auth_return";
      servicesAuthCookieDomain = ".${publicBaseDomain}";
      authGatewayBaseUrl = "http://127.0.0.1:${toString servicesAuthGatewayPort}";
      traefikDokployUpstream = "http://127.0.0.1:81";
      acmeCertName = publicBaseDomain;
      acmeCertDirectory = config.security.acme.certs.${acmeCertName}.directory;
      # lego's IONOS provider reads a raw API key from the referenced file.
      ionosAcmeCredentialsFile = pkgs.writeText "ionos-acme-api-key" ionosApiKey;
      mkProtectedServiceRouter =
        {
          rule,
          service,
          priority ? null,
          middlewares ? [ ],
        }:
        {
          inherit rule service;
          entryPoints = [ "websecure" ];
          middlewares = [ "services-auth" ] ++ middlewares;
          tls = { };
        }
        // lib.optionalAttrs (priority != null) {
          inherit priority;
        };
      mkDirectService = port: {
        loadBalancer.servers = [
          {
            url = "http://127.0.0.1:${toString port}";
          }
        ];
      };
      wildcardUnauthenticatedHosts = [ ];
      wildcardUnauthenticatedRouters = builtins.listToAttrs (
        map (hostname: {
          name = "wildcard-${lib.replaceStrings [ "." "*" ] [ "-" "wildcard" ] hostname}";
          value = {
            rule = "Host(`${hostname}`)";
            service = "dokploy-traefik";
            entryPoints = [ "websecure" ];
            tls = { };
          };
        }) wildcardUnauthenticatedHosts
      );
    in
    {
      services.services-auth-gateway = {
        enable = true;
        bindAddress = "127.0.0.1";
        port = servicesAuthGatewayPort;
        publicDomain = publicBaseDomain;
        cookieDomain = servicesAuthCookieDomain;
        cookieName = servicesAuthCookieName;
        returnCookieName = servicesAuthReturnCookieName;
        defaultRedirect = "https://${apexDomain}/";
        password = servicesAuthPassword;
        signingKey = servicesAuthSigningKey;
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
          # The shared edge auth cookie now lives in Traefik middleware so one
          # login still covers mongo-express together with the other dashboards.
          ME_CONFIG_BASICAUTH = "false";

          # This overrides the hard-coded "mongo" host.
          ME_CONFIG_MONGODB_URL = "mongodb://127.0.0.1:27017/?authSource=admin";
        };
        # Removed --network=host to properly use port mapping and isolate
      };

      services.traefik = {
        enable = true;
        staticConfigOptions = {
          entryPoints = {
            web = {
              address = ":80";
              asDefault = true;
              http.redirections.entryPoint = {
                to = "websecure";
                scheme = "https";
              };
            };
            websecure = {
              address = ":443";
              asDefault = true;
            };
          };
        };
        dynamicConfigOptions = {
          http = {
            middlewares = {
              services-auth.forwardAuth = {
                address = "${authGatewayBaseUrl}/api/forward-auth";
                trustForwardHeader = true;
                addAuthCookiesToResponse = [ servicesAuthReturnCookieName ];
              };
            };
            routers = {
              apex = mkProtectedServiceRouter {
                rule = "Host(`${apexDomain}`) || Host(`${wwwDomain}`)";
                service = "dokploy-traefik";
                priority = 150;
              };
              auth-site = {
                rule = "Host(`${authDomain}`)";
                service = "services-auth-gateway";
                entryPoints = [ "websecure" ];
                tls = { };
              };
              openclaw = {
                rule = "Host(`${openclawDomain}`)";
                service = "dokploy-traefik";
                entryPoints = [ "websecure" ];
                tls = { };
              };
              dashboard = mkProtectedServiceRouter {
                rule = "Host(`${dashboardDomain}`)";
                service = "dashboard";
              };
              netdata = mkProtectedServiceRouter {
                rule = "Host(`${netdataDomain}`)";
                service = "netdata";
              };
              mitmproxy = mkProtectedServiceRouter {
                rule = "Host(`${mitmproxyDomain}`)";
                service = "mitmproxy";
              };
              vpn = mkProtectedServiceRouter {
                rule = "Host(`${vpnDomain}`)";
                service = "vpn";
              };
              cliproxyapi = {
                rule = "Host(`${cliproxyapiDomain}`)";
                service = "cliproxyapi";
                entryPoints = [ "websecure" ];
                tls = { };
              };
              dokploy = mkProtectedServiceRouter {
                rule = "Host(`${dokployDomain}`)";
                service = "dokploy-traefik";
              };
              mongo = mkProtectedServiceRouter {
                rule = "Host(`${mongoDomain}`)";
                service = "mongo";
              };
              wildcard = {
                # Traefik v3 defaults to regex-based HostRegexp syntax, so the
                # old named-placeholder form no longer matches arbitrary
                # subdomains unless ruleSyntax = v2 is set explicitly.
                rule = "HostRegexp(`^[a-z0-9-]+\\.${wildcardDomainPattern}$`)";
                service = "dokploy-traefik";
                entryPoints = [ "websecure" ];
                middlewares = [ "services-auth" ];
                priority = 1;
                tls = { };
              };
            }
            // wildcardUnauthenticatedRouters;
            services = {
              services-auth-gateway = mkDirectService servicesAuthGatewayPort;
              dashboard = mkDirectService 8082;
              netdata = mkDirectService 19999;
              mitmproxy = mkDirectService 8083;
              vpn = mkDirectService 10802;
              cliproxyapi = mkDirectService 8317;
              mongo = mkDirectService 41275;
              dokploy-traefik.loadBalancer.servers = [
                {
                  url = traefikDokployUpstream;
                }
              ];
            };
          };
          tls.certificates = [
            {
              certFile = "${acmeCertDirectory}/fullchain.pem";
              keyFile = "${acmeCertDirectory}/key.pem";
            }
          ];
        };
      };

      security.acme = {
        acceptTerms = true;
        defaults.email = "hostmaster@${publicBaseDomain}"; # Generic mailbox keeps certificate notices off personal addresses.
        certs.${acmeCertName} = {
          domain = acmeCertName;
          extraDomainNames = [ "*.${acmeCertName}" ];
          dnsProvider = "ionos";
          credentialFiles = {
            IONOS_API_KEY_FILE = ionosAcmeCredentialsFile;
          };
          group = config.services.traefik.group;
          reloadServices = [ "traefik.service" ];
        };
      };

      systemd.services.traefik = {
        after = [ "acme-${acmeCertName}.service" ];
        requires = [ "acme-${acmeCertName}.service" ];
      };

      # Persist uploaded images and ACME certificates across reboots.
      # Without this, user images are lost and Let's Encrypt rate-limits hit on every reboot.
      impermanence.nixos.directories = [
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
      networking.firewall.allowedUDPPorts = [ 443 ];
    };
}
