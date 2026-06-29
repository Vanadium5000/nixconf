# Docker Compose stacks — declarative one-directory-per-stack systemd units.
# Drop *.yaml/*.yml files below modules/docker/compose/<stack>/ and enable the stack here;
# each enabled stack runs `docker compose up -d --remove-orphans` on start and `down` on stop.
{ self, ... }:
{
  flake.nixosModules.docker-compose-stacks =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (lib)
        attrNames
        concatMapStringsSep
        filterAttrs
        hasSuffix
        listToAttrs
        mapAttrs
        mapAttrsToList
        mkEnableOption
        mkIf
        mkMerge
        mkOption
        nameValuePair
        optionalAttrs
        types
        ;

      cfg = config.services.docker-compose-stacks;
      composeRoot = ../../docker/compose;
      composeRootEntries = builtins.readDir composeRoot;
      yamlFilesIn =
        dir:
        let
          entries = builtins.readDir dir;
          yamlEntries = filterAttrs (
            name: type: type == "regular" && (hasSuffix ".yaml" name || hasSuffix ".yml" name)
          ) entries;
        in
        map (name: dir + "/${name}") (attrNames yamlEntries);
      discoveredStacks = mapAttrs (
        name: type:
        if type == "directory" then
          { files = yamlFilesIn (composeRoot + "/${name}"); }
        else
          { files = [ ]; }
      ) (filterAttrs (_name: type: type == "directory") composeRootEntries);
      defaultEnabled = {
        portainer = true;
      };
      enabledStacks = filterAttrs (
        name: stack: (cfg.stacks.${name}.enable or false) && stack.files != [ ]
      ) cfg.stacks;
      composeFileArgs =
        files: concatMapStringsSep " " (file: "-f ${lib.escapeShellArg (toString file)}") files;
      dockerCompose = "${pkgs.docker-compose}/bin/docker-compose";
      stackServiceName = name: "docker-compose-stack-${name}";
      mkStackService =
        name: stack:
        let
          serviceName = stackServiceName name;
          composeArgs = composeFileArgs stack.files;
          preStart = pkgs.writeShellScript "${serviceName}-pre-start" ''
            set -euo pipefail
            ${stack.preStart}
          '';
          start = pkgs.writeShellScript "${serviceName}-start" ''
            set -euo pipefail
            export COMPOSE_PROJECT_NAME=${lib.escapeShellArg name}
            export COMPOSE_IGNORE_ORPHANS=false
            ${stack.environmentScript}
            exec ${dockerCompose} ${composeArgs} up -d --remove-orphans
          '';
          stop = pkgs.writeShellScript "${serviceName}-stop" ''
            set -euo pipefail
            export COMPOSE_PROJECT_NAME=${lib.escapeShellArg name}
            ${stack.environmentScript}
            exec ${dockerCompose} ${composeArgs} down --remove-orphans
          '';
        in
        nameValuePair serviceName {
          description = "Docker Compose stack ${name}";
          wantedBy = [ "multi-user.target" ];
          after = [ "docker.service" ];
          requires = [ "docker.service" ];
          path = [ pkgs.docker-compose ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            WorkingDirectory = toString (composeRoot + "/${name}");
            ExecStartPre = preStart;
            ExecStart = start;
            ExecStop = stop;
            TimeoutStartSec = "5min";
            TimeoutStopSec = "2min";
          }
          // optionalAttrs (stack.credentials != [ ]) {
            LoadCredential = stack.credentials;
          };
        };

      qbittorrentConfig = pkgs.writeText "qbittorrent-vpn.conf" ''
        [BitTorrent]
        Session\DefaultSavePath=/downloads
        Session\DisableAutoTMMByDefault=false
        Session\DisableAutoTMMTriggers\CategoryChanged=false
        Session\DisableAutoTMMTriggers\DefaultSavePathChanged=false
        Session\DisableAutoTMMTriggers\CategorySavePathChanged=false
        Session\Port=0
        Session\QueueingSystemEnabled=true
        Session\TempPath=/downloads/incomplete
        Session\TempPathEnabled=true
        Session\UseAlternativeGlobalDLSpeedLimit=false
        Session\UseAlternativeGlobalUPSpeedLimit=false
        Session\UseRandomPort=false
        Session\UPnP=false

        [LegalNotice]
        Accepted=true

        [Meta]
        MigrationVersion=8

        [Network]
        PortForwardingEnabled=false
        Proxy\OnlyForTorrents=false

        [Preferences]
        Connection\Interface=tun0
        Connection\InterfaceName=tun0
        Connection\PortRangeMin=0
        Connection\UPnP=false
        General\Locale=en
        WebUI\Address=*
        WebUI\AlternativeUIEnabled=false
        WebUI\AuthSubnetWhitelist=127.0.0.1/32
        WebUI\AuthSubnetWhitelistEnabled=true
        WebUI\CSRFProtection=true
        WebUI\ClickjackingProtection=true
        WebUI\HostHeaderValidation=false
        WebUI\LocalHostAuth=false
        WebUI\Port=8080
        WebUI\ServerDomains=*
        WebUI\UseUPnP=false
      '';

      gluetunQbittorrentPreStart = ''
        install -d -m 0750 -o 1000 -g 1000 /var/lib/qbittorrent-vpn/config/qBittorrent ${config.preferences.paths.homeDirectory}/Torrents
        if [ ! -s /var/lib/qbittorrent-vpn/config/qBittorrent/qBittorrent.conf ]; then
          install -m 0640 -o 1000 -g 1000 ${qbittorrentConfig} /var/lib/qbittorrent-vpn/config/qBittorrent/qBittorrent.conf
        fi
        ${pkgs.python3}/bin/python3 - /var/lib/qbittorrent-vpn/config/qBittorrent/qBittorrent.conf <<'PY'
        from pathlib import Path
        import base64
        import hashlib
        import os
        import sys

        path = Path(sys.argv[1])
        credentials_dir = Path(os.environ["CREDENTIALS_DIRECTORY"])
        webui_username = (credentials_dir / "qbittorrent-webui-username").read_text().strip()
        webui_password = (credentials_dir / "qbittorrent-webui-password").read_bytes().strip()
        salt = os.urandom(16)
        key = hashlib.pbkdf2_hmac("sha512", webui_password, salt, 100000, dklen=64)
        password_hash = (
            '"@ByteArray('
            + base64.b64encode(salt).decode()
            + ":"
            + base64.b64encode(key).decode()
            + ')"'
        )
        required = {
            "BitTorrent/Session\\Port": "0",
            "BitTorrent/Session\\UseRandomPort": "false",
            "BitTorrent/Session\\UPnP": "false",
            "Network/PortForwardingEnabled": "false",
            "Preferences/Connection\\Interface": "tun0",
            "Preferences/Connection\\InterfaceName": "tun0",
            "Preferences/Connection\\UPnP": "false",
            "Preferences/WebUI\\Address": "*",
            "Preferences/WebUI\\AuthSubnetWhitelist": "127.0.0.1/32",
            "Preferences/WebUI\\AuthSubnetWhitelistEnabled": "true",
            "Preferences/WebUI\\CSRFProtection": "true",
            "Preferences/WebUI\\ClickjackingProtection": "true",
            "Preferences/WebUI\\HostHeaderValidation": "false",
            "Preferences/WebUI\\LocalHostAuth": "false",
            "Preferences/WebUI\\Password_PBKDF2": password_hash,
            "Preferences/WebUI\\Port": "8080",
            "Preferences/WebUI\\ServerDomains": "*",
            "Preferences/WebUI\\Username": webui_username,
            "Preferences/WebUI\\UseUPnP": "false",
        }

        lines = path.read_text().splitlines()
        seen = set()
        out = []
        section = None
        for line in lines:
            stripped = line.strip()
            if stripped.startswith("[") and stripped.endswith("]"):
                section = stripped[1:-1]
                out.append(line)
                continue
            key = None
            if section and "=" in line and not stripped.startswith(("#", ";")):
                raw_key = line.split("=", 1)[0]
                key = f"{section}/{raw_key}"
            if key in required:
                out.append(f"{raw_key}={required[key]}")
                seen.add(key)
            else:
                out.append(line)

        by_section = {}
        for key, value in required.items():
            if key not in seen:
                section_name, option = key.split("/", 1)
                by_section.setdefault(section_name, []).append(f"{option}={value}")

        if by_section:
            if out and out[-1] != "":
                out.append("")
            for section_name, entries in by_section.items():
                out.append(f"[{section_name}]")
                out.extend(entries)
                out.append("")

        path.write_text("\n".join(out).rstrip() + "\n")
        PY
        chown 1000:1000 /var/lib/qbittorrent-vpn/config/qBittorrent/qBittorrent.conf
        chmod 0640 /var/lib/qbittorrent-vpn/config/qBittorrent/qBittorrent.conf
      '';

      gluetunQbittorrentEnvironment = ''
        export PIA_OPENVPN_USER_FILE="$CREDENTIALS_DIRECTORY/pia-openvpn-username"
        export PIA_OPENVPN_PASSWORD_FILE="$CREDENTIALS_DIRECTORY/pia-openvpn-password"
        export QBITTORRENT_DOWNLOADS_DIR=${lib.escapeShellArg "${config.preferences.paths.homeDirectory}/Torrents"}
      '';

      portainerEnvironment = ''
        export PORTAINER_ADMIN_PASSWORD_FILE="$CREDENTIALS_DIRECTORY/portainer-admin-password"
      '';
    in
    {
      options.services.docker-compose-stacks = {
        enable = mkEnableOption "Docker Compose stack systemd units" // {
          default = true;
        };

        stacks = mkOption {
          description = "Discovered Docker Compose stack directories under modules/docker/compose.";
          type = types.attrsOf (
            types.submodule {
              options = {
                enable = mkOption {
                  type = types.bool;
                  default = false;
                  description = "Whether to start this Compose stack at boot.";
                };
                files = mkOption {
                  type = types.listOf types.path;
                  default = [ ];
                  description = "Compose YAML files to pass to docker-compose in order.";
                };
                preStart = mkOption {
                  type = types.lines;
                  default = "";
                  description = "Root shell commands run before compose up.";
                };
                environmentScript = mkOption {
                  type = types.lines;
                  default = "";
                  description = "Shell exports evaluated before compose up/down.";
                };
                credentials = mkOption {
                  type = types.listOf types.str;
                  default = [ ];
                  description = "systemd LoadCredential entries for this stack.";
                };
              };
            }
          );
          default = discoveredStacks;
        };
      };

      config = mkIf cfg.enable (mkMerge [
        {
          virtualisation.docker.enable = true;
          virtualisation.oci-containers.backend = "docker";

          services.docker-compose-stacks.stacks = mkMerge [
            (mapAttrs (name: _stack: {
              enable = lib.mkDefault (defaultEnabled.${name} or false);
              files = lib.mkDefault discoveredStacks.${name}.files;
            }) discoveredStacks)
            {
              gluetun-qbittorrent = {
                preStart = gluetunQbittorrentPreStart;
                environmentScript = gluetunQbittorrentEnvironment;
                credentials = [
                  "pia-openvpn-username:${pkgs.writeText "pia-openvpn-username" self.secrets.PIA_OPENVPN_USERNAME}"
                  "pia-openvpn-password:${pkgs.writeText "pia-openvpn-password" self.secrets.PIA_OPENVPN_PASSWORD}"
                  "qbittorrent-webui-username:${pkgs.writeText "qbittorrent-webui-username" self.secrets.QBITTORRENT_WEBUI_USERNAME}"
                  "qbittorrent-webui-password:${pkgs.writeText "qbittorrent-webui-password" self.secrets.QBITTORRENT_WEBUI_PASSWORD}"
                ];
              };
              portainer = {
                environmentScript = portainerEnvironment;
                credentials = [
                  "portainer-admin-password:${pkgs.writeText "portainer-admin-password" self.secrets.PORTAINER_ADMIN_PASSWORD}"
                ];
              };
            }
          ];

          systemd.services = listToAttrs (mapAttrsToList mkStackService enabledStacks);
        }
      ]);
    };
}
