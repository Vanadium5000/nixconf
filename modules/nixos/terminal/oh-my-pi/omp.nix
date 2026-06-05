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
      configSourceDirectory = config.preferences.paths.configSourceDirectory;
      system = pkgs.stdenv.hostPlatform.system;
      modelsCommand = self.packages.${system}.models;
      piApiKey = self.secrets.OMNIROUTE_PI_API_KEY or "";
      exaApiKey = self.secrets.EXA_API_KEY or "";
      opencodeApiKey = self.secrets.OMNIROUTE_OPENCODE_API_KEY or "";

      ompDirectory = "${homeDirectory}/.omp";
      ompAgentDirectory = "${ompDirectory}/agent";
      ompModelsFile = "${ompAgentDirectory}/models.yml";
      ompConfigFile = "${ompAgentDirectory}/config.yml";
      # OMP's pi-ai aborts OpenAI-family streams when no first SSE event arrives
      # before PI_STREAM_FIRST_EVENT_TIMEOUT_MS. OmniRoute can exceed the 100s
      # default during upstream routing/cold starts; keep a finite watchdog so a
      # dead stream still aborts instead of hanging the session indefinitely.
      # Source: @oh-my-pi/pi-ai src/utils/idle-iterator.ts and src/providers/openai-completions.ts.
      streamFirstEventTimeoutMs = 300000;
      shellUser = lib.escapeShellArg user;
      shellHomeDirectory = lib.escapeShellArg homeDirectory;
      shellConfigSourceDirectory = lib.escapeShellArg configSourceDirectory;
      shellOmpDirectory = lib.escapeShellArg ompDirectory;
      shellOmpAgentDirectory = lib.escapeShellArg ompAgentDirectory;
      shellOmpModelsFile = lib.escapeShellArg ompModelsFile;
      shellOmpConfigFile = lib.escapeShellArg ompConfigFile;

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
      options.programs.omp.enable = mkEnableOption "OMP mutable state persistence";

      config = mkIf cfg.enable {
        # Create only directories and OMP's provider timeout hint; existing
        # config.yml, DBs, sessions, logs, and plugins remain regular mutable
        # files for the app. `models sync-omp` writes the documented
        # ~/.omp/agent/models.yml schema from the repo model cache without
        # fetching network data.
        # Source: https://github.com/can1357/oh-my-pi/blob/main/docs/models.md.
        system.activationScripts.omp-user-files = {
          text = ''
            install -d -m 0700 -o ${shellUser} -g users ${shellOmpDirectory}
            install -d -m 0700 -o ${shellUser} -g users ${shellOmpAgentDirectory}
            install -d -m 0700 -o ${shellUser} -g users ${shellOmpAgentDirectory}/sessions
            install -d -m 0700 -o ${shellUser} -g users ${shellOmpAgentDirectory}/terminal-sessions
            install -d -m 0700 -o ${shellUser} -g users ${shellOmpDirectory}/logs
            install -d -m 0700 -o ${shellUser} -g users ${shellOmpDirectory}/plugins

            if [ ! -e ${shellOmpConfigFile} ]; then
              printf '{}\n' > ${shellOmpConfigFile}
            fi

            ${pkgs.yq-go}/bin/yq -i '.retry.provider.timeoutMs = ${toString streamFirstEventTimeoutMs}' ${shellOmpConfigFile}
            chmod 0600 ${shellOmpConfigFile}
            chown ${shellUser}:users ${shellOmpConfigFile}

            if [ ! -e ${shellOmpModelsFile} ]; then
              if [ -z ${lib.escapeShellArg piApiKey} ]; then
                echo "OMNIROUTE_PI_API_KEY is required for OMP models; add system/omniroute/pi-api-key to pass and rerun rebuild.sh." >&2
                exit 1
              fi

              ${pkgs.util-linux}/bin/runuser -u ${shellUser} -- env \
                HOME=${shellHomeDirectory} \
                MODELS_OMP_FILE=${shellOmpModelsFile} \
                MODELS_OMP_API_KEY=${lib.escapeShellArg piApiKey} \
                MODELS_STATE_DIR=${shellConfigSourceDirectory}/modules/nixos/terminal/opencode \
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

        environment.variables = {
          # OMP loads env first, then .env files; exposing these password-store
          # secrets here makes agent web_search and model sync work in fresh
          # shells without copying API keys into mutable ~/.omp files. Source:
          # https://github.com/can1357/oh-my-pi/blob/main/docs/environment-variables.md
          EXA_API_KEY = exaApiKey;
          OMNIROUTE_OPENCODE_API_KEY = opencodeApiKey;
          OMNIROUTE_PI_API_KEY = piApiKey;
          PI_STREAM_FIRST_EVENT_TIMEOUT_MS = toString streamFirstEventTimeoutMs;
        };

        preferences.zsh = {
          aliases.o = "omp";

          aliases.q = qCommand;
          history.ignorePatterns = [
            "q(|[[:space:]]*)"
          ];
        };
      };
    };
}
