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
      # same generated secrets surface so proxy/auth changes stay declarative.
      secrets' = builtins.intersectAttrs (keysAsAttrs [
        "IONOS_API_KEY"
        "MY_WEBSITE_ENV"
        "SERVICES_AUTH_PASSWORD"
      ]) self.secrets;
      envText = secrets'.MY_WEBSITE_ENV;
      ionosApiKey = secrets'.IONOS_API_KEY;
      servicesAuthPassword = secrets'.SERVICES_AUTH_PASSWORD;
      frontendPackage = inputs.my-website-frontend.packages.${pkgs.stdenv.hostPlatform.system}.default;
      frontendRoot = "${frontendPackage}";
      frontendPort = 41272;
      servicesAuthGatewayPort = 41276;
      servicesAuthSigningKey = builtins.hashString "sha256" "${servicesAuthPassword}:my-website.space:services-auth-gateway";
      servicesAuthCookieName = "__Secure-services_auth";
      servicesAuthReturnCookieName = "__Secure-services_auth_return";
      servicesAuthCookieDomain = ".my-website.space";
      authGatewayBaseUrl = "http://127.0.0.1:${toString servicesAuthGatewayPort}";
      traefikDokployUpstream = "http://127.0.0.1:81";
      acmeCertName = "my-website.space";
      acmeCertDirectory = config.security.acme.certs.${acmeCertName}.directory;
      # lego's IONOS provider reads a raw API key from the referenced file.
      ionosAcmeCredentialsFile = pkgs.writeText "ionos-acme-api-key" ionosApiKey;
      staticSiteScript = pkgs.writeText "my-website-frontend-server.py" ''
        import http.server
        import os
        import socketserver


        ROOT = ${builtins.toJSON frontendRoot}
        PORT = ${toString frontendPort}


        class Handler(http.server.SimpleHTTPRequestHandler):
            def __init__(self, *args, **kwargs):
                super().__init__(*args, directory=ROOT, **kwargs)

            def do_GET(self):
                path = self.translate_path(self.path)
                if self.path.startswith("/backend/") or self.path.startswith("/auth/api/"):
                    self.send_error(404)
                    return
                if os.path.exists(path) or self.path.endswith("/"):
                    return super().do_GET()
                self.path = "/index.html"
                return super().do_GET()

            def log_message(self, format, *args):
                return


        class ThreadingTCPServer(socketserver.ThreadingTCPServer):
            allow_reuse_address = True


        with ThreadingTCPServer(("127.0.0.1", PORT), Handler) as httpd:
            httpd.serve_forever()
      '';
      staticSiteName = "my-website-frontend";
      staticSiteExecutable = pkgs.writeShellApplication {
        name = staticSiteName;
        runtimeInputs = [ pkgs.python3 ];
        text = ''
          exec ${pkgs.python3}/bin/python3 ${staticSiteScript}
        '';
      };
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

      systemd.services.${staticSiteName} = {
        description = "Static frontend server for my-website.space";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        serviceConfig = {
          Type = "simple";
          DynamicUser = true;
          ExecStart = "${staticSiteExecutable}/bin/${staticSiteName}";
          Restart = "on-failure";
          RestartSec = 5;
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          WorkingDirectory = frontendRoot;
        };
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
              apex = {
                rule = "Host(`my-website.space`) || Host(`www.my-website.space`)";
                service = "frontend";
                entryPoints = [ "websecure" ];
                tls = { };
              };
              backend = {
                rule = "Host(`my-website.space`) && PathPrefix(`/backend/`)";
                service = "backend";
                entryPoints = [ "websecure" ];
                priority = 200;
                tls = { };
              };
              drfrost-solver = {
                rule = "Host(`my-website.space`) && PathPrefix(`/backend/drfrost-solver/`)";
                service = "drfrost-solver";
                entryPoints = [ "websecure" ];
                priority = 210;
                tls = { };
              };
              auth-api = {
                rule = "Host(`my-website.space`) && PathPrefix(`/auth/api/`)";
                service = "backend-auth-api";
                entryPoints = [ "websecure" ];
                priority = 220;
                tls = { };
              };
              auth-site = {
                rule = "Host(`auth.my-website.space`)";
                service = "services-auth-gateway";
                entryPoints = [ "websecure" ];
                tls = { };
              };
              openclaw = {
                rule = "Host(`openclaw.my-website.space`)";
                service = "dokploy-traefik";
                entryPoints = [ "websecure" ];
                tls = { };
              };
              dashboard = mkProtectedServiceRouter {
                rule = "Host(`dashboard.my-website.space`)";
                service = "dashboard";
              };
              netdata = mkProtectedServiceRouter {
                rule = "Host(`netdata.my-website.space`)";
                service = "netdata";
              };
              mitmproxy = mkProtectedServiceRouter {
                rule = "Host(`mitmproxy.my-website.space`)";
                service = "mitmproxy";
              };
              vpn = mkProtectedServiceRouter {
                rule = "Host(`vpn.my-website.space`)";
                service = "vpn";
              };
              cliproxyapi = mkProtectedServiceRouter {
                rule = "Host(`cliproxyapi.my-website.space`)";
                service = "cliproxyapi";
              };
              dokploy = mkProtectedServiceRouter {
                rule = "Host(`dokploy.my-website.space`)";
                service = "dokploy-traefik";
              };
              mongo = mkProtectedServiceRouter {
                rule = "Host(`mongo.my-website.space`)";
                service = "mongo";
              };
              wildcard = {
                rule = "HostRegexp(`{subdomain:[a-z0-9-]+}.my-website.space`)";
                service = "dokploy-traefik";
                entryPoints = [ "websecure" ];
                middlewares = [ "services-auth" ];
                priority = 1;
                tls = { };
              };
            }
            // wildcardUnauthenticatedRouters;
            services = {
              frontend.loadBalancer.servers = [
                {
                  url = "http://127.0.0.1:${toString frontendPort}";
                }
              ];
              backend = mkDirectService 41273;
              drfrost-solver = mkDirectService 41274;
              backend-auth-api = mkDirectService 41273;
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
        defaults.email = "vanadium5000@gmail.com"; # Required for cert issuance.
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
      networking.firewall.allowedUDPPorts = [ 443 ];
    };
}
