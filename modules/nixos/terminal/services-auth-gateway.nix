{ ... }:
{
  flake.nixosModules.services-auth-gateway =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (lib)
        mkEnableOption
        mkIf
        mkOption
        types
        ;
      cfg = config.services.services-auth-gateway;
      configFile = pkgs.writeText "services-auth-gateway-config.json" (
        builtins.toJSON {
          bindAddress = cfg.bindAddress;
          port = cfg.port;
          publicDomain = cfg.publicDomain;
          cookieDomain = cfg.cookieDomain;
          cookieName = cfg.cookieName;
          returnCookieName = cfg.returnCookieName;
          defaultRedirect = cfg.defaultRedirect;
          sessionTtlSeconds = cfg.sessionTtlSeconds;
          returnTtlSeconds = cfg.returnTtlSeconds;
          password = cfg.password;
          signingKey = cfg.signingKey;
        }
      );
    in
    {
      options.services.services-auth-gateway = {
        enable = mkEnableOption "lightweight shared-cookie auth gateway";

        package = mkOption {
          type = types.package;
          default = pkgs.customPackages.services-auth-gateway;
          description = "Package providing the auth gateway HTTP service";
        };

        bindAddress = mkOption {
          type = types.str;
          default = "127.0.0.1";
          description = "Local address for the auth gateway so nginx stays the only public edge";
        };

        port = mkOption {
          type = types.port;
          default = 41276;
          description = "Local HTTP port for nginx auth_request checks and the shared login form";
        };

        publicDomain = mkOption {
          type = types.str;
          default = "my-website.space";
          description = "Public suffix allowed for post-login redirects";
        };

        cookieDomain = mkOption {
          type = types.str;
          default = ".my-website.space";
          description = "Cookie scope shared across protected service subdomains";
        };

        cookieName = mkOption {
          type = types.str;
          default = "__Secure-services_auth";
          description = "Session cookie name shared across service subdomains";
        };

        returnCookieName = mkOption {
          type = types.str;
          default = "__Secure-services_auth_return";
          description = "Short-lived redirect cookie so login can send users back where they started";
        };

        sessionTtlSeconds = mkOption {
          type = types.ints.positive;
          default = 604800; # 7d
          description = "Session lifetime in seconds before nginx requires another login";
        };

        returnTtlSeconds = mkOption {
          type = types.ints.positive;
          default = 300; # 5m
          description = "Short redirect-cookie lifetime so stale return targets do not linger";
        };

        defaultRedirect = mkOption {
          type = types.str;
          default = "https://my-website.space/";
          description = "Fallback redirect when the login flow has no valid original destination";
        };

        password = mkOption {
          type = types.str;
          description = "Shared password accepted by the lightweight login form";
        };

        signingKey = mkOption {
          type = types.str;
          description = "Secret used to sign cookie sessions so nginx can trust auth_request responses";
        };
      };

      config = mkIf cfg.enable {
        users.users.services-auth-gateway = {
          isSystemUser = true;
          group = "services-auth-gateway";
          home = "/var/lib/services-auth-gateway";
          description = "Shared auth gateway service user";
        };
        users.groups.services-auth-gateway = { };

        systemd.services.services-auth-gateway = {
          description = "Shared auth gateway for my-website.space services";
          wantedBy = [ "multi-user.target" ];
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];

          serviceConfig = {
            Type = "simple";
            User = "services-auth-gateway";
            Group = "services-auth-gateway";
            ExecStart = "${cfg.package}/bin/services-auth-gateway --config ${configFile}";
            Restart = "on-failure";
            RestartSec = 5;
            NoNewPrivileges = true;
            PrivateTmp = true;
            PrivateDevices = true;
            ProtectHome = true;
            ProtectSystem = "strict";
            StateDirectory = "services-auth-gateway";
            WorkingDirectory = "/var/lib/services-auth-gateway";
          };
        };

        impermanence.nixos.directories = [
          {
            directory = "/var/lib/services-auth-gateway";
            user = "services-auth-gateway";
            group = "services-auth-gateway";
            mode = "0750";
          }
        ];
      };
    };
}
