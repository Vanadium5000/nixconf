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
        mkEnableOption
        mkIf
        mkOption
        optional
        types
        ;
      cfg = config.services.opensnitch;
      json = pkgs.formats.json { };
      dataDir = "/var/lib/opensnitch";
      user = config.preferences.user.username;
      userRuntimeDir = "/run/user/${toString config.users.users.${user}.uid}";
      uiSocket = "unix://${userRuntimeDir}/opensnitch/osui.sock";
      defaultConfig = "${dataDir}/default-config.json";
      systemFirewallConfig = "${dataDir}/system-fw.json";
      managedAt = "2026-07-09T00:00:00Z";

      operatorType = types.submodule {
        freeformType = json.type;
        options = {
          type = mkOption {
            type = types.enum [
              "simple"
              "regexp"
              "network"
              "lists"
              "list"
              "range"
            ];
            description = "OpenSnitch operator matcher type.";
          };
          operand = mkOption {
            type = types.str;
            description = "Connection field to compare, for example process.path, process.command, dest.host, dest.port, process.env.NAME, or list.";
          };
          data = mkOption {
            type = types.str;
            default = "";
            description = "Matcher data: literal value, Go RE2 regexp, network range, list directory, or range expression depending on type.";
          };
          sensitive = mkOption {
            type = types.bool;
            default = false;
            description = "Whether OpenSnitch should compare this operator case-sensitively.";
          };
          list = mkOption {
            type = types.nullOr (types.listOf operatorType);
            default = null;
            description = "Nested operators for type=list. OpenSnitch ANDs all nested operators.";
          };
        };
      };

      ruleType = types.submodule (
        { name, ... }:
        {
          freeformType = json.type;
          options = {
            created = mkOption {
              type = types.str;
              default = managedAt;
              description = "Rule creation timestamp serialized into the OpenSnitch JSON file.";
            };
            updated = mkOption {
              type = types.str;
              default = managedAt;
              description = "Rule update timestamp serialized into the OpenSnitch JSON file.";
            };
            name = mkOption {
              type = types.str;
              default = name;
              description = "OpenSnitch rule name. Rule files and rule evaluation sort lexicographically by this value.";
            };
            description = mkOption {
              type = types.str;
              default = "";
              description = "Human-readable rule rationale shown in OpenSnitch UI.";
            };
            enabled = mkOption {
              type = types.bool;
              default = true;
              description = "Whether OpenSnitch should load and evaluate the rule.";
            };
            precedence = mkOption {
              type = types.bool;
              default = false;
              description = "OpenSnitch priority flag; matching priority rules stop evaluation according to upstream precedence semantics.";
            };
            nolog = mkOption {
              type = types.bool;
              default = false;
              description = "Whether OpenSnitch should suppress event logging for matches.";
            };
            action = mkOption {
              type = types.enum [
                "allow"
                "deny"
                "reject"
              ];
              description = "Rule verdict. reject terminates the socket immediately; deny drops packets.";
            };
            duration = mkOption {
              type = types.str;
              default = "always";
              description = "OpenSnitch duration string. Disk-backed declarative rules should normally use always.";
            };
            operator = mkOption {
              type = operatorType;
              description = "Typed OpenSnitch operator tree.";
            };
          };
        }
      );

      op = type: operand: data: {
        inherit type operand data;
        sensitive = false;
        list = null;
      };
      simple = op "simple";
      regexp = op "regexp";
      network = op "network";
      list = operators: {
        type = "list";
        operand = "list";
        data = "";
        sensitive = false;
        list = operators;
      };
      rule = name: description: action: operator: {
        inherit
          name
          description
          action
          operator
          ;
        created = managedAt;
        updated = managedAt;
        duration = "always";
        enabled = true;
        precedence = false;
        nolog = false;
      };
      priority = rule: rule // { precedence = true; };

      baseRules = {
        "000-allow-authenticated-root-bypass" = priority (
          rule "000-allow-authenticated-root-bypass"
            "Allow commands launched through opensnitch-bypass after polkit/sudo authentication; guarded by uid 0 plus an environment marker."
            "allow"
            (list [
              (simple "user.id" "0")
              (simple "process.env.NIXCONF_OPENSNITCH_BYPASS" "authenticated-root")
            ])
        );
        "000-allow-localhost-ipv4" = priority (
          rule "000-allow-localhost-ipv4"
            "Allow loopback IPv4; desktop components, agents, D-Bus helpers, and local proxies use localhost IPC."
            "allow"
            (network "dest.network" "127.0.0.0/8")
        );
        "000-allow-localhost-ipv6" = priority (
          rule "000-allow-localhost-ipv6" "Allow loopback IPv6 for the same localhost IPC paths as IPv4."
            "allow"
            (network "dest.network" "::1/128")
        );
        "001-reject-ld-preload-network" = priority (
          rule "001-reject-ld-preload-network"
            "Reject outbound sockets from processes carrying LD_PRELOAD paths; upstream documents process.env matching for this malware pattern."
            "reject"
            (regexp "process.env.LD_PRELOAD" "^(\\.|/).*")
        );
        "001-reject-temp-executables" = priority (
          rule "001-reject-temp-executables"
            "Reject executables launched from writable temp/runtime locations before broad allow rules can match."
            "reject"
            (regexp "process.path" "^(/memfd|/tmp/|/var/tmp/|/dev/shm/|/var/run|/var/lock).*")
        );
      };

      settingsSeed = json.generate "opensnitch-settings.json" cfg.settings;
      mutableRuleFiles = mapAttrs (
        name: rule: json.generate "opensnitch-rule-${name}.json" rule
      ) cfg.mutableRules;
      managedRuleNames = mapAttrsToList (name: _: "${name}.json") cfg.mutableRules;
      opensnitchBypassRoot = pkgs.writeShellScriptBin "opensnitch-bypass-root" ''
        set -euo pipefail
        if [ "$#" -lt 1 ]; then
          printf 'usage: opensnitch-bypass -- command [args...]\n' >&2
          exit 64
        fi
        if [ "$(${pkgs.coreutils}/bin/id -u)" -ne 0 ]; then
          printf 'opensnitch-bypass-root must run as root via pkexec/sudo.\n' >&2
          exit 126
        fi
        export NIXCONF_OPENSNITCH_BYPASS=authenticated-root
        exec "$@"
      '';
      opensnitchBypass = pkgs.writeShellScriptBin "opensnitch-bypass" ''
        set -euo pipefail
        if [ "$#" -lt 1 ]; then
          printf 'usage: opensnitch-bypass -- command [args...]\n' >&2
          exit 64
        fi
        if [ "$1" = "--" ]; then
          shift
        fi
        if [ "$#" -lt 1 ]; then
          printf 'usage: opensnitch-bypass -- command [args...]\n' >&2
          exit 64
        fi
        if [ "$(${pkgs.coreutils}/bin/id -u)" -eq 0 ]; then
          exec ${opensnitchBypassRoot}/bin/opensnitch-bypass-root "$@"
        fi
        exec ${pkgs.polkit}/bin/pkexec ${opensnitchBypassRoot}/bin/opensnitch-bypass-root "$@"
      '';
      opensnitchUi = pkgs.symlinkJoin {
        name = "opensnitch-ui-with-private-socket";
        paths = [ pkgs.opensnitch-ui ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/opensnitch-ui \
            --add-flags ${escapeShellArg "--socket ${uiSocket}"}
        '';
      };
      mutableConfigSeed = pkgs.runCommand "opensnitch-default-config.json" { } ''
        ${getExe pkgs.jq} -s '.[0] * .[1]' \
          ${cfg.package}/etc/opensnitchd/default-config.json \
          ${settingsSeed} \
          > "$out"
      '';
    in
    {
      options.services.opensnitch.nixconf = {
        baseRules.enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable the repository's process-agnostic OpenSnitch baseline rules for desktop hosts.";
        };
        bypassWrapper.enable = mkEnableOption "authenticated opensnitch-bypass wrapper" // {
          default = true;
        };
      };

      options.services.opensnitch.mutableRules = mkOption {
        default = { };
        type = types.attrsOf ruleType;
        description = ''
          Declarative OpenSnitch rule files under `${dataDir}/rules`.

          These files are deliberately writable at runtime so OpenSnitch UI can
          inspect and temporarily edit them, but the directory is reset from Nix
          on activation/service start. Keep durable rules here, not only in the
          UI state. Operator trees are typed while still permitting upstream JSON
          extensions through freeform attributes.
        '';
        example = lib.literalExpression ''
          {
            allow-example = {
              action = "allow";
              duration = "always";
              operator = {
                type = "list";
                operand = "list";
                list = [
                  { type = "simple"; operand = "process.path"; data = "''${pkgs.curl}/bin/curl"; }
                  { type = "simple"; operand = "dest.host"; data = "example.com"; }
                  { type = "simple"; operand = "dest.port"; data = "443"; }
                ];
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
        ]
        ++ optional cfg.nixconf.bypassWrapper.enable opensnitchBypass;

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
          mutableRules = mkIf cfg.nixconf.baseRules.enable baseRules;
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
          "C+ ${defaultConfig} 0640 root root - ${mutableConfigSeed}"
          "C+ ${systemFirewallConfig} 0640 root root - ${cfg.package}/etc/opensnitchd/system-fw.json"
        ]
        ++ (mapAttrsToList (
          name: file: "C+ ${dataDir}/rules/${name}.json 0600 root root - ${file}"
        ) mutableRuleFiles);

        systemd.services.opensnitchd = {
          after = mkAfter [ "systemd-tmpfiles-setup.service" ];
          wants = mkAfter [ "systemd-tmpfiles-setup.service" ];
          preStart = mkBefore ''
            install -d -m 0750 ${dataDir} ${dataDir}/rules ${dataDir}/lists
            install -m 0640 ${mutableConfigSeed} ${defaultConfig}
            install -m 0640 ${cfg.package}/etc/opensnitchd/system-fw.json ${systemFirewallConfig}
            ${pkgs.findutils}/bin/find ${dataDir}/rules -maxdepth 1 -type f -name '*.json' -delete
            ${concatMapStringsSep "\n" (
              { name, file }:
              ''
                install -m 0600 ${file} ${dataDir}/rules/${name}.json
              ''
            ) (mapAttrsToList (name: file: { inherit name file; }) mutableRuleFiles)}
            printf '%s\n' ${escapeShellArg (builtins.concatStringsSep "\n" managedRuleNames)} > ${dataDir}/rules/.nix-managed
            chmod 0640 ${dataDir}/rules/.nix-managed
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
