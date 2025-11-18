{ self, inputs, ... }:
{
  flake.nixosModules.ionos_vpsHost =
    { pkgs, ... }:
    let
      secrets' = self.secrets [
        "MY_WEBSITE_ENV"
        "MONGODB_PASSWORD"
      ];
      envText = secrets'.MY_WEBSITE_ENV;
      mongodbPassword = secrets'.MONGODB_PASSWORD;
      mongodbPasswordFile = pkgs.writeText "mongodb-password" mongodbPassword;
    in
    {
      imports = [
        inputs.my-website-backend.nixosModules.default
      ];

      # Enable backend service
      services.my-website-backend = {
        enable = true;
        envFile = pkgs.writeText ".env" envText;
      };

      # Run mongo-express in a container (isolated & easy)
      virtualisation.oci-containers.containers.mongo-express = {
        autoStart = true;
        image = "mongoexpress/mongo-express:latest";
        ports = [ "127.0.0.1:8081:8081" ]; # Only localhost
        environment = {
          ME_CONFIG_MONGODB_SERVER = "localhost";
          ME_CONFIG_MONGODB_PORT = "27017";
          ME_CONFIG_MONGODB_ENABLE_ADMIN = "true";
          ME_CONFIG_MONGODB_ADMINUSERNAME = "root";
          ME_CONFIG_BASICAUTH_USERNAME = "admin";
        };
        environmentFiles = [
          (pkgs.writeText "mongo-express-env" ''
            ME_CONFIG_MONGODB_ADMINPASSWORD=${mongodbPassword}
            ME_CONFIG_BASICAUTH_PASSWORD=${mongodbPassword}
          '')
        ];
        extraOptions = [
          "--network=pasta" # NixOS 25.05+ default, resolves host.containers.internal
        ];
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
          root = "${inputs.my-website-frontend.packages.${pkgs.system}.default}";

          # Proxy backend (adjust path if needed)
          locations."/backend/" = {
            proxyPass = "http://127.0.0.1:3000/";
            proxyWebsockets = true; # If needed for WS
          };

          # New auth proxy (preserves /auth/api/ path)
          locations."/auth/api/" = {
            proxyPass = "http://127.0.0.1:3000"; # No trailing / to preserve path
            proxyWebsockets = true;
            # Add other proxy settings like proxy_set_header Host $host; etc.
          };

          # Optional: SPA fallback for frontend routes
          locations."/" = {
            tryFiles = "$uri $uri/ /index.html";
          };
        };

        virtualHosts."mongo.my-website.space" = {
          forceSSL = true;
          enableACME = true;
          locations."/" = {
            proxyPass = "http://127.0.0.1:8081/";
            extraConfig = ''
              auth_basic "MongoDB Admin";
              auth_basic_user_file ${mongodbPasswordFile};
            '';
          };
        };
      };

      # ACME (Let's Encrypt) setup
      security.acme = {
        acceptTerms = true;
        defaults.email = "vanadium5000@gmail.com"; # Required for cert issuance
      };

      # Open firewall for HTTP/HTTPS
      networking.firewall.allowedTCPPorts = [
        80
        443
      ];

      # Additional security: Enable fail2ban for brute-force protection
      services.fail2ban.enable = true;
    };
}
