{ self, ... }:
{
  flake.nixosModules.omp =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    let
      cfg = config.programs.omp;
      inherit (lib) mkEnableOption mkIf;

      user = config.preferences.user.username;
      homeDirectory = config.preferences.paths.homeDirectory;
      configDirectory = config.preferences.paths.configDirectory;
      system = pkgs.stdenv.hostPlatform.system;
      modelsCommand = self.packages.${system}.models;

      ompDirectory = "${homeDirectory}/.omp";
      ompAgentDirectory = "${ompDirectory}/agent";
      ompModelsFile = "${ompAgentDirectory}/models.yml";
      ompQuestionConfigFile = "${ompAgentDirectory}/config-q.yml";
      shellUser = lib.escapeShellArg user;
      shellHomeDirectory = lib.escapeShellArg homeDirectory;
      shellConfigDirectory = lib.escapeShellArg configDirectory;
      shellOmpDirectory = lib.escapeShellArg ompDirectory;
      shellOmpAgentDirectory = lib.escapeShellArg ompAgentDirectory;
      shellOmpModelsFile = lib.escapeShellArg ompModelsFile;
      shellOmpQuestionConfigFile = lib.escapeShellArg ompQuestionConfigFile;

      # Persist the whole OpenAgent/OMP tree because local inspection shows it mixes
      # mutable DBs, logs, plugins, and editable YAML under ~/.omp and ~/.omp/agent.
      # Source: observed local paths ~/.omp/{agent,logs,plugins,gpu_cache.json}.
      ompPersistence = self.lib.persistence.mkPersistent {
        method = "bind";
        inherit user;
        fileName = "omp";
        targetFile = ompDirectory;
        isDirectory = true;
      };
    in
    {
      options.programs.omp.enable = mkEnableOption "OpenAgent/OMP mutable state persistence";

      config = mkIf cfg.enable {
        # Create only directories and OMP's first-run custom model catalog; config.yml,
        # DBs, sessions, logs, and plugins remain regular mutable files for the app.
        # `models sync-omp` writes the documented ~/.omp/agent/models.yml schema
        # from the repo model cache without fetching network data.
        # Source: https://github.com/can1357/oh-my-pi/blob/main/docs/models.md.
        system.activationScripts.omp-user-files = {
          text = ''
            install -d -m 0700 -o ${shellUser} -g users ${shellOmpDirectory}
            install -d -m 0700 -o ${shellUser} -g users ${shellOmpAgentDirectory}
            install -d -m 0700 -o ${shellUser} -g users ${shellOmpAgentDirectory}/sessions
            install -d -m 0700 -o ${shellUser} -g users ${shellOmpAgentDirectory}/terminal-sessions
            install -d -m 0700 -o ${shellUser} -g users ${shellOmpDirectory}/logs
            install -d -m 0700 -o ${shellUser} -g users ${shellOmpDirectory}/plugins
            install -m 0600 -o ${shellUser} -g users ${pkgs.writeText "omp-question-config.yml" ''
              edit:
                mode: hashline
              tools:
                discoveryMode: off
                essentialOverride:
                  - web_search
              find:
                enabled: false
              search:
                enabled: false
              astGrep:
                enabled: false
              astEdit:
                enabled: false
              lsp:
                enabled: false
              browser:
                enabled: false
              bashInterceptor:
                enabled: true
            ''} ${shellOmpQuestionConfigFile}

            if [ ! -e ${shellOmpModelsFile} ]; then
              ${pkgs.util-linux}/bin/runuser -u ${shellUser} -- env \
                HOME=${shellHomeDirectory} \
                MODELS_OMP_FILE=${shellOmpModelsFile} \
                MODELS_STATE_DIR=${shellConfigDirectory}/modules/nixos/terminal/opencode \
                ${modelsCommand}/bin/models sync-omp >/dev/null
              chmod 0600 ${shellOmpModelsFile}
              chown ${shellUser}:users ${shellOmpModelsFile}
            fi
          '';
          deps = [ "users" ];
        };

        system.activationScripts.omp-persistence = {
          text = ompPersistence.activationScript;
          deps = [ "users" ];
        };

        fileSystems = ompPersistence.fileSystems;

        preferences.zsh = {
          aliases.q = "PI_CODING_AGENT_DIR=${ompAgentDirectory} omp --no-session --no-skills --no-rules --no-title --no-lsp --tools web_search -p";
          history.ignorePatterns = [
            "q(|[[:space:]]*)"
          ];
        };
      };
    };
}
