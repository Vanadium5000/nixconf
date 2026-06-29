{ self, ... }:
{
  flake.nixosModules.cockpit =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.cockpit-managed;
      listenStream =
        if cfg.host == "0.0.0.0" then toString cfg.port else "${cfg.host}:${toString cfg.port}";
    in
    {
      options.services.cockpit-managed = {
        enable = lib.mkEnableOption "Cockpit system administration panel";

        host = lib.mkOption {
          type = lib.types.str;
          default = "127.0.0.1";
          description = "Address Cockpit listens on; use 0.0.0.0 only behind trusted network/auth controls.";
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 9090;
          description = "TCP port for the Cockpit web panel.";
        };

        openFirewall = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to open the Cockpit port in the host firewall.";
        };

        user = lib.mkOption {
          type = lib.types.str;
          default = "cockpit-admin";
          description = "Local account used for Cockpit PAM login.";
        };

        hashedPassword = lib.mkOption {
          type = lib.types.str;
          default = self.secrets.COCKPIT_ADMIN_HASHED_PASSWORD;
          defaultText = lib.literalExpression ''
            (pass field "hashedpassword" from system/cockpit-admin via self.secrets.COCKPIT_ADMIN_HASHED_PASSWORD)
          '';
          description = "Hashed password field from the Cockpit password-store credential.";
        };
      };

      config = lib.mkIf cfg.enable {
        assertions = [
          {
            assertion = !(cfg.host == "0.0.0.0" && cfg.openFirewall);
            message = "services.cockpit-managed.host = 0.0.0.0 must not be combined with services.cockpit-managed.openFirewall.";
          }
        ];

        services.cockpit = {
          enable = true;
          port = cfg.port;
          openFirewall = cfg.openFirewall;
          showBanner = false;
          allowed-origins = [ "*" ];
          plugins = [ pkgs.cockpit-files ];
          settings.WebService = {
            AllowUnencrypted = true;
            LoginTo = false;
            AllowMultiHost = false;
          };
        };

        environment.systemPackages = [ pkgs.wireguard-tools ];

        # Empty ListenStream first clears Cockpit's packaged socket before adding our bind;
        # otherwise systemd keeps both entries and switch fails with EADDRINUSE on 9090.
        systemd.sockets.cockpit.listenStreams = lib.mkForce [
          ""
          listenStream
        ];

        users.users.${cfg.user} = {
          isNormalUser = true;
          home = "/var/lib/${cfg.user}";
          createHome = true;
          group = cfg.user;
          extraGroups = [ "wheel" ];
          shell = pkgs.bashInteractive;
          hashedPassword = cfg.hashedPassword;
        };
        users.groups.${cfg.user} = { };
      };
    };
}
