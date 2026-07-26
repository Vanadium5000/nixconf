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
        selfpkgs.git-identity
        selfpkgs.m
        selfpkgs.markdown-lint-mcp
        selfpkgs.models
        selfpkgs.openports
        selfpkgs.qalc
        selfpkgs.rebuild
      ]
      ++ lib.optionals (hostName != "main_vps") [
        selfpkgs.lyricsctl
        selfpkgs.synced-lyrics
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

        # VPN Proxy Services (SOCKS5 + HTTP CONNECT)
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
          # PASSWORD_STORE_DIR for stuff like qs-passmenu
          PASSWORD_STORE_DIR = "$HOME/.local/share/password-store";
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
