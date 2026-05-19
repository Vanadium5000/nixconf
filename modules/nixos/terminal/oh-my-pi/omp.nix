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
      piApiKey = self.secrets.OMNIROUTE_PI_API_KEY or "";

      ompDirectory = "${homeDirectory}/.omp";
      ompAgentDirectory = "${ompDirectory}/agent";
      ompModelsFile = "${ompAgentDirectory}/models.yml";
      shellUser = lib.escapeShellArg user;
      shellHomeDirectory = lib.escapeShellArg homeDirectory;
      shellConfigDirectory = lib.escapeShellArg configDirectory;
      shellOmpDirectory = lib.escapeShellArg ompDirectory;
      shellOmpAgentDirectory = lib.escapeShellArg ompAgentDirectory;
      shellOmpModelsFile = lib.escapeShellArg ompModelsFile;

      qSystemPrompt = "You are q. Answer directly in plain text, concise by default. Use web_search for current web facts, read for URLs, and python for calculations or code evaluation. Cite web sources when used. Say when you do not know.";
      qCommand = lib.escapeShellArgs [
        "env"
        "PI_CODING_AGENT_DIR=${ompAgentDirectory}"
        "NULL_PROMPT=true"
        "omp"
        "--no-session"
        "--no-skills"
        "--no-rules"
        "--no-extensions"
        "--no-title"
        "--no-lsp"
        "--no-tools"
        "--tools"
        "web_search,read,python"
        "--system-prompt"
        qSystemPrompt
        "-p"
      ];
      # Persist the whole OMOS/OMP tree because local inspection shows it mixes
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
      options.programs.omp.enable = mkEnableOption "OMOS/OMP mutable state persistence";

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

            if [ ! -e ${shellOmpModelsFile} ]; then
              if [ -z ${lib.escapeShellArg piApiKey} ]; then
                echo "OMNIROUTE_PI_API_KEY is required for OMP models; add system/omniroute/pi-api-key to pass and rerun rebuild.sh." >&2
                exit 1
              fi

              ${pkgs.util-linux}/bin/runuser -u ${shellUser} -- env \
                HOME=${shellHomeDirectory} \
                MODELS_OMP_FILE=${shellOmpModelsFile} \
                MODELS_OMP_API_KEY=${lib.escapeShellArg piApiKey} \
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
          aliases.q = qCommand;
          history.ignorePatterns = [
            "q(|[[:space:]]*)"
          ];
        };
      };
    };
}
