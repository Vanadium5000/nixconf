{ self, ... }:
{
  flake.nixosModules.terminal =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      cfg = lib.attrByPath [ "preferences" "profiles" "terminal" ] { enable = false; } config;
      hostName = lib.attrByPath [ "preferences" "hostName" ] null config;

      selfpkgs = self.packages.${pkgs.stdenv.hostPlatform.system};
      environmentShell = selfpkgs.environment;
      terminalFlakePackages = [
        environmentShell
      ];
    in
    {
      imports = [
        # Requirements
        self.nixosModules.common
        self.nixosModules.zsh
        self.nixosModules.environment-user-packages-cache

        # Opencode
        self.nixosModules.opencode
        self.nixosModules.omp
        self.nixosModules.dev
        self.nixosModules.nix
        self.nixosModules.memory
        self.nixosModules.btrfs-maintenance
        self.nixosModules.btrbk-persist-system
        self.nixosModules.tailscale
        self.nixosModules.virtualisation
        self.nixosModules.nixconf-docs
        self.nixosModules.docker-compose-stacks
        self.nixosModules.unison

        # VPN proxy services are package-owned so their runtime closure and
        # persistence contract travel together.
        self.nixosModules.vpn-proxy-service

        # Server services (disabled by default, enable per-host)
        self.nixosModules.bifrost
        self.nixosModules.cliproxyapi
        self.nixosModules.cpa-usage-keeper
        self.nixosModules.omniroute
        self.nixosModules.services-auth-gateway
      ];

      config = lib.mkIf cfg.enable {
        security.polkit.enable = true;

        security.wrappers.pkexec = {
          # Enable the setuid bit → this is the critical part that makes pkexec actually work
          # Without this you get the famous "pkexec must be setuid root" error
          setuid = true;

          # The owner must be root – this is required for setuid to have any meaning
          owner = "root";

          # Group is traditionally also root (very common convention for setuid wrappers)
          # Changing it rarely makes sense unless you have very special requirements
          group = "root";

          # Source path: where the real (non-wrapped) pkexec binary lives
          # ${pkgs.polkit} expands to the current polkit package in your nixpkgs version
          # This line basically says: "wrap this particular binary and give it the s-bit"
          source = "${pkgs.polkit}/bin/pkexec";
        };

        hardware.enableRedistributableFirmware = true;

        programs.direnv.enable = true;
        programs.direnv.nix-direnv.enable = true;

        # OMP/OMOS keeps mutable DBs, logs, plugins, and YAML under ~/.omp;
        # enable the bootstrap with terminal hosts so impermanence preserves that tree.
        # Source: local state layout observed at ~/.omp/agent/{config.yml,models.yml}.
        programs.omp.enable = lib.mkDefault true;
        preferences.btrbkPersistSystem.enable = lib.mkDefault true;

        # GitHub CLI auth/config is durable terminal profile state; request and
        # extension caches are cache-tier. Source: gh XDG config/cache layout.
        impermanence.home.directories = [
          ".config/gh"
        ];
        impermanence.home.cache.directories = [
          ".cache/gh"
        ];

        # Git-sync, a utility to sync folders via git
        services.git-sync.enable = true;

        preferences.zsh.aliases.gi = "git-identity setup";
        preferences.zsh.aliases.g = "git-identity setup";
        preferences.zsh.aliases.r = "rebuild";
        preferences.commandHelp.commands = [
          {
            command = "rebuild";
            aliases = [ "r" ];
            description = "Run the Nixconf host rebuild, validation, and maintenance wrapper.";
            usage = "HOST=<host> rebuild [OPTIONS] [ACTION] [TARGET]";
            details = "Use rebuild --help for actions. Validation is safe here; switch, deploy, install, and rollback intentionally change host state.";
            package = selfpkgs.rebuild;
          }
          {
            command = "models";
            description = "Manage the shared OpenCode and OMP model catalog and runtime configuration.";
            usage = "models [sync|sync-all|sync-opencode|sync-config|sync-omp|select <category> <router/model> [reasoning-level]|omp-categories|preset-apply|provider|init]";
            package = selfpkgs.models;
          }
          {
            command = "markdown-lint-mcp";
            description = "Run the configured Markdown lint MCP server used by OpenCode.";
            usage = "markdown-lint-mcp";
            package = selfpkgs.bunjs-markdown-lint-mcp;
          }
          {
            command = "qmllint-mcp";
            description = "Run the configured QML and Qt lint MCP server used by OpenCode.";
            usage = "qmllint-mcp";
            package = selfpkgs.bunjs-qmllint-mcp;
          }
          {
            command = "quickshell-docs-mcp";
            description = "Run the configured Quickshell documentation MCP server used by OpenCode.";
            usage = "quickshell-docs-mcp";
            package = selfpkgs.bunjs-quickshell-docs-mcp;
          }
          {
            command = "openports";
            description = "Show currently-open NixOS firewall ports and accept rules.";
            usage = "openports";
            details = "Prompts through the system sudo wrapper and only inspects live iptables state.";
            package = selfpkgs.openports;
          }
          {
            command = "qalc";
            description = "Open the interactive Qalculate calculator with automatic calculation enabled.";
            usage = "qalc [expression]";
            package = selfpkgs.qalc;
          }
        ]
        ++ lib.optionals (hostName != "main_vps") [
          {
            command = "lyricsctl";
            description = "Display, control, and fetch synced lyrics for the active media player.";
            usage = "lyricsctl [watch|current|status|lookup|sources|show|hide|toggle|control|seek|tui] [options]";
            package = selfpkgs.lyricsctl;
          }
        ];
        services.nixconf-docs.enable = true;

        # Password-store folder
        services.git-sync.repositories = {
          passwords = {
            uri = "github.com:Vanadium5000/passwords.git";
            path = "${config.preferences.paths.homeDirectory}/.local/share/password-store";
            interval = 300;
            user = config.preferences.user.username;
            identity = "password-store";
          };
        };

        # Environment Variables
        environment.variables = {
          # GUI launchers do not expand `$HOME` in /etc/set-environment.
          PASSWORD_STORE_DIR = "${config.preferences.paths.homeDirectory}/.local/share/password-store";
          FLAKE = config.preferences.paths.configDirectory; # Config Directory
          NIXCONF_CONFIG_SOURCE = config.preferences.paths.configSourceDirectory;
        };

        # Add environment packages to system packages
        environment.systemPackages =
          terminalFlakePackages
          ++ (with pkgs; [
            # SSH clients can forward TERM=xterm-ghostty; installing only the
            # terminfo output avoids pulling the Ghostty GUI onto terminal hosts.
            # Source: /etc/set-environment re-exports TERM after TERMINFO_DIRS.
            ghostty.terminfo
            parted
            exfatprogs
            gh # Github CLI

            wtype
            monero-cli
            electrum
            electrum-ltc
            foundry # provides "cast"
          ]);

        users.users.${config.preferences.user.username}.shell = environmentShell;
        environment.shells = [ environmentShell ];

        # Declare the HOST as an environment variable for use in scripts, etc.
        environment.variables.HOST = config.preferences.hostName;
      };
    };
}
