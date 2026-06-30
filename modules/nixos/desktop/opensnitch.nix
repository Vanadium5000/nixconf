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
        getExe
        escapeShellArg
        mkAfter
        mkBefore
        mkIf
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
        ];

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
