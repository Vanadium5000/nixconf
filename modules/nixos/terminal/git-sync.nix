{ ... }:
{
  flake.nixosModules.terminal =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (lib)
        literalExpression
        mkIf
        mkOption
        types
        ;

      cfg = config.services.git-sync;
      user = config.preferences.user.username;

      # Pre-start script to ensure GPG agent is ready and can show pinentry GUI
      # This is critical for SSH key authentication via gpg-agent
      preStartScript = pkgs.writeShellScript "git-sync-prestart" ''
        set -euo pipefail

        # Ensure GPG_TTY is set for the current session
        export GPG_TTY=$(tty 2>/dev/null || echo "/dev/pts/0")

        # Tell gpg-agent about our TTY so pinentry can spawn
        ${pkgs.gnupg}/bin/gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1 || true

        # Test SSH authentication is working (non-blocking check)
        # This warms up the agent and may trigger pinentry if key is locked
        timeout 5 ${pkgs.openssh}/bin/ssh-add -l >/dev/null 2>&1 || true

        echo "git-sync pre-start: GPG/SSH environment ready"
      '';

      # Function to create a systemd unit configuration for Linux
      mkUnit = name: repo: {
        enable = true;
        description = "Git Sync ${name}";

        # Start when graphical session is ready (ensures WAYLAND_DISPLAY etc. are set)
        wantedBy = [ "graphical-session.target" ];

        # Tie lifecycle to graphical session
        partOf = [ "graphical-session.target" ];

        # Wait for network to be online before starting
        after = [
          "graphical-session.target"
          "network-online.target"
        ];
        wants = [ "network-online.target" ];

        serviceConfig = {
          Type = "simple";

          # Environment variables for git-sync operation
          Environment = [
            "PATH=${
              lib.makeBinPath (
                with pkgs;
                [
                  openssh
                  git
                  gnupg
                  coreutils
                ]
                ++ repo.extraPackages
              )
            }"
            "GIT_SYNC_DIRECTORY=${lib.strings.escapeShellArg repo.path}"
            "GIT_SYNC_COMMAND=${cfg.package}/bin/git-sync"
            "GIT_SYNC_REPOSITORY=${lib.strings.escapeShellArg repo.uri}"
            "GIT_SYNC_INTERVAL=${toString repo.interval}"
            # GPG agent socket location (NixOS default)
            "GNUPGHOME=/home/${user}/.gnupg"
          ];

          # Import environment from graphical session for display/GPG/SSH access
          # This is critical for pinentry-qt to show GUI prompts
          PassEnvironment = [
            "WAYLAND_DISPLAY"
            "DISPLAY"
            "XDG_RUNTIME_DIR"
            "GPG_TTY"
            "SSH_AUTH_SOCK"
            "DBUS_SESSION_BUS_ADDRESS"
          ];

          ExecStartPre = "${preStartScript}";
          ExecStart = "${cfg.package}/bin/git-sync-on-inotify";

          # Restart configuration for maximum reliability
          Restart = "always";
          RestartSec = "3min"; # 3 minute delay between restarts

          WorkingDirectory = repo.path;
        };

        unitConfig = {
          # No limit on restart attempts (survives long network outages)
          StartLimitIntervalSec = 0;
        };
      };

      # Function to create a launchd daemon configuration for Darwin
      mkAgent = name: repo: {
        enable = true;
        config = {
          UserName = repo.user; # Run as the specified user
          StartInterval = repo.interval;
          ProcessType = "Background";
          WorkingDirectory = repo.path;
          WatchPaths = [ repo.path ];
          ProgramArguments = [ "${cfg.package}/bin/git-sync" ];
        };
      };

      # Select the appropriate service creator based on the platform
      mkService = if pkgs.stdenv.isLinux then mkUnit else mkAgent;

      # Generate services for each repository
      services = lib.mapAttrs' (name: repo: {
        name = "git-sync-${name}";
        value = mkService name repo;
      }) cfg.repositories;

      # Submodule type for each repository configuration
      repositoryType = types.submodule (
        { name, ... }:
        {
          options = {
            name = mkOption {
              internal = true;
              default = name;
              type = types.str;
              description = "The name that should be given to this unit.";
            };
            path = mkOption {
              type = types.path;
              description = "The path at which to sync the repository.";
            };
            uri = mkOption {
              type = types.str;
              example = "git+ssh://user@example.com:/~[user]/path/to/repo.git";
              description = ''
                The URI of the remote to be synchronized. This is only used in the
                event that the directory does not already exist. See
                <https://git-scm.com/docs/git-clone#_git_urls>
                for the supported URIs.
                This option is not supported on Darwin.
              '';
            };
            interval = mkOption {
              type = types.int;
              default = 500;
              description = ''
                The interval, specified in seconds, at which the synchronization will
                be triggered even without filesystem changes.
              '';
            };
            extraPackages = mkOption {
              type = with types; listOf package;
              default = [ ];
              example = literalExpression "with pkgs; [ git-crypt ]";
              description = ''
                Extra packages available to git-sync.
              '';
            };
            user = mkOption {
              type = types.str;
              default = "root";
              description = ''
                The user as which to run the git-sync service.
              '';
            };
          };
        }
      );
    in
    {
      # Module options
      options = {
        services.git-sync = {
          enable = lib.mkEnableOption "git-sync services";
          package = lib.mkPackageOption pkgs "git-sync" { };
          repositories = mkOption {
            type = with types; attrsOf repositoryType;
            default = { };
            description = ''
              The repositories that should be synchronized.
            '';
            example = literalExpression ''
              {
                example = {
                  path = "/var/lib/git-sync/example";
                  uri = "git@github.com:example/repo.git";
                  interval = 1000;
                  user = "gituser";
                };
              }
            '';
          };
        };
      };

      # Module configuration
      config = mkIf cfg.enable (
        lib.mkMerge [
          # Remove ".user." for a non user-level systemd service
          (mkIf pkgs.stdenv.isLinux { systemd.user.services = services; })
          # (mkIf pkgs.stdenv.isDarwin { launchd.daemons = services; })
        ]
      );
    };
}
