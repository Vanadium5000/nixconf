{ self, inputs, ... }:
{
  flake.nixosModules.ionos_vpsHost =
    { pkgs, ... }:
    let
      inherit (self) secrets;

      envText = (secrets [ "MY_WEBSITE_ENV" ]).MY_WEBSITE_ENV;
    in
    {
      imports = [
        inputs.my-website-backend.nixosModules.default
      ];

      # Enable services
      services.my-website-backend = {
        enable = true; # Starts the my-website-backend
        envFile = pkgs.writeText ".env" envText;
      };

      services.nginx = {
        enable = true;
        recommendedGzipSettings = true;
        recommendedOptimisation = true;
        recommendedProxySettings = true;
        recommendedTlsSettings = true;

        virtualHosts."my-website.space" = {
          serverAliases = [ "www.my-website.space" ];

          addSSL = true; # Redirect HTTP to HTTPS
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
            proxyPass = "http://127.0.0.1:3000"; # The lack of a trailing / on proxy_pass in the auth block ensures the full path (/auth/api/*) is forwarded to your backend server at port 3000
            proxyWebsockets = true; # If needed for WS
            # Add other proxy settings like proxy_set_header Host $host; etc.
          };

          # Optional: SPA fallback for frontend routes
          locations."/" = {
            tryFiles = "$uri $uri/ /index.html";
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
    };
}
