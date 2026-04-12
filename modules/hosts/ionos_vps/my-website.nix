{ self, inputs, ... }:
{
  flake.nixosModules.ionos_vpsHost =
    {
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

      # Get the secrets sub-object with the required secrets
      secrets' = builtins.intersectAttrs (keysAsAttrs [
        "MY_WEBSITE_ENV"
        "MONGODB_PASSWORD"
        "MONGO_EXPRESS_PASSWORD"
        "SERVICES_AUTH_PASSWORD"
      ]) self.secrets;
      envText = secrets'.MY_WEBSITE_ENV;
      # mongodbPassword = secrets'.MONGODB_PASSWORD;
      mongoExpressPassword = secrets'.MONGO_EXPRESS_PASSWORD;
      servicesAuthPassword = secrets'.SERVICES_AUTH_PASSWORD;
      # Multiple usernames with one shared password keeps Basic Auth simple
      # while avoiding lock-in to a single hardcoded username.
      servicesAuthUsers = [
        "admin"
        "main"
        "matrix"
      ];
      # mongoExpressPasswordFile = pkgs.writeText "mongo-express-password" mongoExpressPassword;

      # Helper for authenticated subdomains
      mkAuthenticatedSubdomain =
        {
          port,
          extraConfig ? "",
          ...
        }:
        {
          forceSSL = true;
          enableACME = true;
          locations."/" = {
            proxyPass = "http://127.0.0.1:${toString port}/";
            proxyWebsockets = true;
            extraConfig =
              let
                htpasswdFile = pkgs.runCommand "htpasswd-services" { } ''
                  ${pkgs.apacheHttpd}/bin/htpasswd -cbB -C 12 \
                    "$out" "${builtins.head servicesAuthUsers}" "${servicesAuthPassword}"
                  ${lib.concatMapStringsSep "\n" (user: ''
                    ${pkgs.apacheHttpd}/bin/htpasswd -bB -C 12 \
                      "$out" "${user}" "${servicesAuthPassword}"
                  '') (builtins.tail servicesAuthUsers)}
                '';
              in
              ''
                # Shared realm improves browser credential reuse across subdomains.
                auth_basic "my-website.space services";
                auth_basic_user_file ${htpasswdFile};
              ''
              + extraConfig;
          };
        };
    in
    {
      imports = [
        inputs.my-website-backend.nixosModules.default
      ];

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
          # ME_CONFIG_MONGODB_ADMINUSERNAME = "root";
          ME_CONFIG_BASICAUTH_USERNAME = "admin";

          # This overrides the hard-coded "mongo" host
          # ME_CONFIG_MONGODB_URL = "mongodb://root:${mongodbPassword}@127.0.0.1:27017/?authSource=admin";
          # No password?
          ME_CONFIG_MONGODB_URL = "mongodb://127.0.0.1:27017/?authSource=admin";
        };
        environmentFiles = [
          (pkgs.writeText "mongo-express-env" ''
            ME_CONFIG_BASICAUTH_PASSWORD=${mongoExpressPassword}
          '')
        ];
        # Removed --network=host to properly use port mapping and isolate
      };

      # Nginx setup
      services.nginx = {
        enable = true;
        recommendedGzipSettings = true;
        recommendedOptimisation = true;
        recommendedProxySettings = true;
        recommendedTlsSettings = true;

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

          # New auth proxy (preserves /auth/api/ path)
          locations."/auth/api/" = {
            proxyPass = "http://127.0.0.1:41273"; # No trailing / to preserve path
            proxyWebsockets = true;
            # NOTE: Update pass entry my_website/env_file APP_URL to use port 41273
          };


          # Optional: SPA fallback for frontend routes
          locations."/" = {
            tryFiles = "$uri $uri/ /index.html";
          };
        };

        virtualHosts."dashboard.my-website.space" = mkAuthenticatedSubdomain {
          port = 8082;
          description = "Fleet Dashboard";
        };

        virtualHosts."netdata.my-website.space" = {
          forceSSL = true;
          enableACME = true;
          locations."= /" = {
            # Netdata on this host exposes API endpoints but no static dashboard at '/'.
            # Redirecting root avoids the upstream "File does not exist" error page.
            return = "302 /api/v1/info";
          };
          locations."/" = {
            proxyPass = "http://127.0.0.1:19999/";
            proxyWebsockets = true;
            extraConfig =
              let
                htpasswdFile = pkgs.runCommand "htpasswd-services" { } ''
                  ${pkgs.apacheHttpd}/bin/htpasswd -cbB -C 12 \
                    "$out" "${builtins.head servicesAuthUsers}" "${servicesAuthPassword}"
                  ${lib.concatMapStringsSep "\n" (user: ''
                    ${pkgs.apacheHttpd}/bin/htpasswd -bB -C 12 \
                      "$out" "${user}" "${servicesAuthPassword}"
                  '') (builtins.tail servicesAuthUsers)}
                '';
              in
              ''
                auth_basic "my-website.space services";
                auth_basic_user_file ${htpasswdFile};
              '';
          };
        };

        virtualHosts."mitmproxy.my-website.space" = mkAuthenticatedSubdomain {
          port = 8083;
          description = "HTTPS Traffic Analyzer";
        };

        virtualHosts."vpn.my-website.space" = mkAuthenticatedSubdomain {
          port = 10802;
          description = "VPN Proxy Management";
        };

        virtualHosts."cliproxyapi.my-website.space" = mkAuthenticatedSubdomain {
          port = 8317;
          description = "CLI Proxy API";
        };

        virtualHosts."openclaw.my-website.space" = mkAuthenticatedSubdomain {
          port = 3100;
          description = "OpenClaw Gateway";
        };

        virtualHosts."opencode.my-website.space" = mkAuthenticatedSubdomain {
          port = 4096;
          description = "OpenCode Server";
        };

        virtualHosts."mongo.my-website.space" = {
          forceSSL = true; # Redirect HTTP to HTTPS
          enableACME = true; # Auto Let's Encrypt
          locations."/" = {
            proxyPass = "http://127.0.0.1:41275/";
            extraConfig =
              let
                htpasswdFile = pkgs.runCommand "htpasswd" { } ''
                  ${pkgs.apacheHttpd}/bin/htpasswd -cbB -C 12 \
                    $out admin "${mongoExpressPassword}"
                '';
              in
              ''
                auth_basic "MongoDB Admin";
                auth_basic_user_file ${htpasswdFile};
              '';
          };
        };
      };

      # FORCE NEW CERTIFICATE FOR "MONGO" SUBDOMAIN
      # security.acme.certs."mongo.my-website.space" = {
      #   domain = "mongo.my-website.space"; # forces cert creation
      #   email = "vanadium5000@gmail.com"; # your email
      #   group = "nginx"; # makes nginx able to read it
      # };

      # ACME (Let's Encrypt) setup
      security.acme = {
        acceptTerms = true;
        defaults.email = "vanadium5000@gmail.com"; # Required for cert issuance
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
