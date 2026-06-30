{ ... }:
{
  flake.nixosModules.opensnitch =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (lib)
        concatMapStringsSep
        escapeShellArg
        getExe
        mapAttrs
        mapAttrsToList
        mkAfter
        mkBefore
        mkIf
        mkOption
        ;
      cfg = config.services.opensnitch;
      json = pkgs.formats.json { };
      dataDir = "/var/lib/opensnitch";
      user = config.preferences.user.username;
      userRuntimeDir = "/run/user/${toString config.users.users.${user}.uid}";
      uiSocket = "unix://${userRuntimeDir}/opensnitch/osui.sock";
      defaultConfig = "${dataDir}/default-config.json";
      systemFirewallConfig = "${dataDir}/system-fw.json";
      settingsSeed = json.generate "opensnitch-settings.json" cfg.settings;
      mutableRuleFiles = mapAttrs (
        name: rule: json.generate "opensnitch-rule-${name}.json" rule
      ) cfg.mutableRules;
      opensnitchUi = pkgs.symlinkJoin {
        name = "opensnitch-ui-with-private-socket";
        paths = [ pkgs.opensnitch-ui ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/opensnitch-ui \
            --add-flags ${escapeShellArg "--socket ${uiSocket}"}
        '';
      };
      localhostIpv4Rule = json.generate "000-allow-localhost-ipv4.json" {
        created = "2026-06-29T00:00:00Z";
        updated = "2026-06-29T00:00:00Z";
        name = "000-allow-localhost-ipv4";
        enabled = true;
        precedence = true;
        action = "allow";
        duration = "always";
        operator = {
          type = "network";
          operand = "dest.network";
          sensitive = false;
          data = "127.0.0.0/8";
          list = [ ];
        };
      };
      localhostIpv6Rule = json.generate "000-allow-localhost-ipv6.json" {
        created = "2026-06-29T00:00:00Z";
        updated = "2026-06-29T00:00:00Z";
        name = "000-allow-localhost-ipv6";
        enabled = true;
        precedence = true;
        action = "allow";
        duration = "always";
        operator = {
          type = "network";
          operand = "dest.network";
          sensitive = false;
          data = "::1/128";
          list = [ ];
        };
      };
      mutableConfigSeed = pkgs.runCommand "opensnitch-default-config.json" { } ''
        ${getExe pkgs.jq} -s '.[0] * .[1]' \
          ${cfg.package}/etc/opensnitchd/default-config.json \
          ${settingsSeed} \
          > "$out"
      '';
    in
    {
      options.services.opensnitch.mutableRules = mkOption {
        default = { };
        type = lib.types.attrsOf (lib.types.submodule { freeformType = json.type; });
        description = ''
          Mutable OpenSnitch rule seeds. Each attribute is written as
          `${dataDir}/rules/<name>.json` with the attribute value encoded as
          JSON, but only when the file does not already exist so the UI can
          keep editing persisted rule files in place.
        '';
        example = lib.literalExpression ''
          {
            allow-example = {
              name = "allow-example";
              action = "allow";
              duration = "always";
              enabled = true;
              operator = {
                type = "simple";
                operand = "dest.host";
                data = "example.com";
                list = [ ];
                sensitive = false;
              };
            };
          }
        '';
      };

      config = mkIf cfg.enable {
        # OpenSnitch's eBPF monitor needs trace/kprobe support and NFQUEUE/nftables
        # queue modules; load them up-front so opensnitchd -check-requirements does
        # not depend on first-connection autoload timing. Source: OpenSnitch wiki
        # daemon-known-problems + monitor-method-ebpf.
        boot.kernelModules = mkAfter [
          "nf_conntrack"
          "nf_defrag_ipv4"
          "nf_defrag_ipv6"
          "nfnetlink_queue"
          "nft_queue"
        ];

        networking.nftables.enable = true;

        environment.systemPackages = [
          cfg.package
          opensnitchUi
        ];

        environment.etc = {
          # The daemon still probes these upstream default paths even with a
          # custom configFile; provide them so startup is clean while primary
          # daemon config/rules remain mutable under /var/lib/opensnitch.
          # Source: opensnitchd v1.8.0 startup log + upstream default data dir.
          "opensnitchd/network_aliases.json".source = "${cfg.package}/etc/opensnitchd/network_aliases.json";
          "opensnitchd/tasks/tasks.json".text = builtins.toJSON { tasks = [ ]; };
        };

        services.opensnitch = {
          package = pkgs.opensnitch;
          configFile = defaultConfig;
          mutableRules = {
            allow-brave = {
              created = "2026-06-30T02:47:21+01:00";
              updated = "2026-06-30T02:47:21+01:00";
              name = "allow-brave";
              description = "Allow Brave";
              action = "allow";
              duration = "always";
              operator = {
                operand = "process.path";
                data = "^/nix/store/[0-9a-z]{32}-brave-origin-[^/]+/opt/brave.com/brave-origin-nightly/brave$";
                type = "regexp";
                list = [ ];
                sensitive = false;
              };
              enabled = true;
              precedence = false;
              nolog = false;
            };
            allow-dms-weather = {
              created = "2026-06-30T02:44:41+01:00";
              updated = "2026-06-30T02:44:41+01:00";
              name = "allow-dms-weather";
              description = "Allow DMS weather";
              action = "allow";
              duration = "always";
              operator = {
                operand = "dest.host";
                data = "api.open-meteo.com";
                type = "simple";
                list = [ ];
                sensitive = false;
              };
              enabled = true;
              precedence = false;
              nolog = false;
            };
            allow-ssh-out = {
              created = "2026-06-30T02:44:49+01:00";
              updated = "2026-06-30T02:44:49+01:00";
              name = "allow-ssh-out";
              description = "Allow SSH out";
              action = "allow";
              duration = "always";
              operator = {
                operand = "process.path";
                data = "^/nix/store/[0-9a-z]{32}-openssh-[^/]+/bin/ssh$";
                type = "regexp";
                list = [ ];
                sensitive = false;
              };
              enabled = true;
              precedence = false;
              nolog = false;
            };
            allow-tailscale = {
              created = "2026-06-30T02:47:06+01:00";
              updated = "2026-06-30T02:47:06+01:00";
              name = "allow-tailscale";
              description = "Allow Tailscale";
              action = "allow";
              duration = "always";
              operator = {
                operand = "process.path";
                data = "^/nix/store/[^/]+-tailscale-[^/]+/bin/.tailscaled-wrapped$";
                type = "regexp";
                list = [ ];
                sensitive = false;
              };
              enabled = true;
              precedence = false;
              nolog = false;
            };
          };
          settings = {
            Server = {
              Address = uiSocket;
              LogFile = "/var/log/opensnitchd.log";
            };
            DefaultAction = "allow";
            DefaultDuration = "once";
            InterceptUnknown = true;
            ProcMonitorMethod = "ebpf";
            Firewall = "nftables";
            FwOptions = {
              ConfigPath = systemFirewallConfig;
              MonitorInterval = "15s";
              ActionOnOverflow = "drop";
            };
            Rules = {
              Path = "${dataDir}/rules";
              EnableChecksums = true;
            };
            Ebpf = {
              EventsWorkers = 8;
              QueueEventsSize = 4096;
            };
            Stats = {
              MaxEvents = 150;
              MaxStats = 25;
              Workers = 6;
            };
          };
        };

        systemd.tmpfiles.rules = [
          "d ${dataDir} 0750 root root - -"
          "d ${dataDir}/rules 0750 root root - -"
          "d ${dataDir}/lists 0750 root root - -"
          "C ${defaultConfig} 0640 root root - ${mutableConfigSeed}"
          "C ${systemFirewallConfig} 0640 root root - ${cfg.package}/etc/opensnitchd/system-fw.json"
          "C ${dataDir}/rules/000-allow-localhost-ipv4.json 0640 root root - ${localhostIpv4Rule}"
          "C ${dataDir}/rules/000-allow-localhost-ipv6.json 0640 root root - ${localhostIpv6Rule}"
        ]
        ++ (mapAttrsToList (
          name: file: "C ${dataDir}/rules/${name}.json 0600 root root - ${file}"
        ) mutableRuleFiles);

        systemd.services.opensnitchd = {
          after = mkAfter [ "systemd-tmpfiles-setup.service" ];
          wants = mkAfter [ "systemd-tmpfiles-setup.service" ];
          preStart = mkBefore ''
            install -d -m 0750 ${dataDir} ${dataDir}/rules ${dataDir}/lists
            if [ ! -e ${defaultConfig} ]; then
              install -m 0640 ${mutableConfigSeed} ${defaultConfig}
            fi
            if [ ! -e ${systemFirewallConfig} ]; then
              install -m 0640 ${cfg.package}/etc/opensnitchd/system-fw.json ${systemFirewallConfig}
            fi
            if [ ! -e ${dataDir}/rules/000-allow-localhost-ipv4.json ]; then
              install -m 0640 ${localhostIpv4Rule} ${dataDir}/rules/000-allow-localhost-ipv4.json
            fi
            if [ ! -e ${dataDir}/rules/000-allow-localhost-ipv6.json ]; then
              install -m 0640 ${localhostIpv6Rule} ${dataDir}/rules/000-allow-localhost-ipv6.json
            fi
            ${concatMapStringsSep "\n" (
              { name, file }:
              ''
                if [ ! -e ${dataDir}/rules/${name}.json ]; then
                  install -m 0600 ${file} ${dataDir}/rules/${name}.json
                fi
              ''
            ) (mapAttrsToList (name: file: { inherit name file; }) mutableRuleFiles)}
          '';
        };

        systemd.user.services.opensnitch-ui = {
          description = "OpenSnitch UI";
          wantedBy = [ "graphical-session.target" ];
          partOf = [ "graphical-session.target" ];
          after = [ "graphical-session.target" ];

          serviceConfig = {
            ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p %t/opensnitch";
            ExecStart = "${opensnitchUi}/bin/opensnitch-ui --background";
            Restart = "on-failure";
            RestartSec = 5;
          };
        };

        impermanence.nixos.directories = [ dataDir ];
        impermanence.home.directories = [ ".config/opensnitch" ];
      };
    };
}
