{ self, ... }:
{
  flake.nixosModules.webmin =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.webmin;
      webminRoot = "${cfg.package}/libexec/webmin";
      configDir = "/etc/webmin";
      varDir = "/var/lib/webmin";
    in
    {
      options.services.webmin = {
        enable = lib.mkEnableOption "Webmin";

        package = lib.mkOption {
          type = lib.types.package;
          default = self.packages.${pkgs.stdenv.hostPlatform.system}.webmin;
          description = "Webmin package to run.";
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 10000;
          description = "TCP port for Webmin's miniserv web server.";
        };

        openFirewall = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to open the Webmin port in the firewall.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.etc = {
          "webmin/config".text = ''
            os_type=generic-linux
            os_version=1.0
            real_os_type=NixOS
            real_os_version=${config.system.nixos.release}
            lang=en
          '';
          "webmin/miniserv.conf".text = ''
            port=${toString cfg.port}
            listen=${toString cfg.port}
            bind=0.0.0.0
            root=${webminRoot}
            mimetypes=${webminRoot}/mime.types
            addtype_cgi=internal/cgi
            realm=Webmin Server
            logfile=${varDir}/miniserv.log
            errorlog=${varDir}/miniserv.error
            pidfile=${varDir}/miniserv.pid
            ppath=
            ssl=1
            no_ssl2=1
            no_ssl3=1
            no_tls1=1
            no_tls1_1=1
            ssl_honorcipherorder=1
            no_sslcompression=1
            env_WEBMIN_CONFIG=${configDir}
            env_WEBMIN_VAR=${varDir}
            atboot=1
            anonymous=/=root
            denyfile=\.pl$
            log=1
            blockhost_failures=5
            blockhost_time=60
            syslog=1
            ipv6=1
            session=1
            premodules=WebminCore
            server=MiniServ
            userfile=${configDir}/miniserv.users
            keyfile=${configDir}/miniserv.pem
            passwd_file=/etc/shadow
            passwd_uindex=0
            passwd_pindex=1
            passwd_cindex=2
            passwd_mindex=4
            passwd_mode=0
            preroot=authentic-theme
            passdelay=1
            logout_script=${webminRoot}/logout.pl
            webprefix=
          '';
          "webmin/miniserv.users".text = ''
            root:x:0::::
          '';
          "webmin/webmin.acl".text = ''
            root: acl webmin servers proc init syslog logviewer cron mount passwd useradmin system-status
          '';
          "webmin/root.acl".source = "${cfg.package}/libexec/webmin/defaultacl";
          "webmin/miniserv.pem".source = "${cfg.package}/libexec/webmin/miniserv.pem";
        };

        security.pam.services.webmin = { };

        systemd.services.webmin = {
          description = "Webmin server";
          wantedBy = [ "multi-user.target" ];
          after = [ "network.target" ];
          serviceConfig = {
            # Webmin intentionally administers host-level services and files; keep the UI reachable only via closed firewall / authenticated proxy.
            # Source: https://webmin.com/docs/intro/
            Type = "simple";
            ExecStart = "${cfg.package}/bin/webmin-miniserv --nofork ${configDir}/miniserv.conf";
            Restart = "on-failure";
            StateDirectory = "webmin";
          };
        };

        networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];
      };
    };
}
