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

      # Function to create a systemd unit configuration for Linux
      mkUnit = name: repo: {
        description = "Git Sync ${name}"; # Service description
        wantedBy = [ "multi-user.target" ]; # Start at multi-user target for system services
        serviceConfig = {
          User = repo.user; # Run as the specified user
          Environment = [
            "PATH=${
              lib.makeBinPath (
                with pkgs;
                [
                  openssh
                  git
                ]
                ++ repo.extraPackages
              )
            }"
            "GIT_SYNC_DIRECTORY=${lib.strings.escapeShellArg repo.path}"
            "GIT_SYNC_COMMAND=${cfg.package}/bin/git-sync"
            "GIT_SYNC_REPOSITORY=${lib.strings.escapeShellArg repo.uri}"
            "GIT_SYNC_INTERVAL=${toString repo.interval}"
          ];
          ExecStart = "${cfg.package}/bin/git-sync-on-inotify";
          Restart = "on-abort";
          WorkingDirectory = repo.path; # Set working directory to the repo path
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
          (mkIf pkgs.stdenv.isLinux { systemd.services = services; })
          # (mkIf pkgs.stdenv.isDarwin { launchd.daemons = services; })
        ]
      );
    };
}
