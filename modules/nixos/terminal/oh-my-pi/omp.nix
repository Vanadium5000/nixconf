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
      languages = import ../opencode/_languages.nix { inherit pkgs self; };
      piApiKey = self.secrets.OMNIROUTE_PI_API_KEY or "";
      exaApiKey = self.secrets.EXA_API_KEY or "";
      opencodeApiKey = self.secrets.OMNIROUTE_OPENCODE_API_KEY or "";

      ompDirectory = "${homeDirectory}/.omp";
      ompAgentDirectory = "${ompDirectory}/agent";
      ompEnvFile = "${ompAgentDirectory}/.env";
      ompLspFile = "${ompAgentDirectory}/lsp.json";
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
      shellOmpEnvFile = lib.escapeShellArg ompEnvFile;
      shellOmpLspFile = lib.escapeShellArg ompLspFile;
      shellOmpModelsFile = lib.escapeShellArg ompModelsFile;
      shellOmpConfigFile = lib.escapeShellArg ompConfigFile;

      ompLspConfigFile = pkgs.writeText "omp-lsp.json" (
        builtins.toJSON {
          idleTimeoutMs = 300000;
          servers = {
            bashls = {
              command = "${pkgs.bash-language-server}/bin/bash-language-server";
              args = [ "start" ];
              fileTypes = [
                ".sh"
                ".bash"
                ".zsh"
              ];
              rootMarkers = [ ".git" ];
              settings.bashIde.globPattern = "*@(.sh|.inc|.bash|.command|.zsh)";
            };
            basedpyright = {
              command = "${pkgs.basedpyright}/bin/basedpyright-langserver";
              args = [ "--stdio" ];
              fileTypes = [
                ".py"
                ".pyi"
              ];
              rootMarkers = [
                "pyproject.toml"
                "pyrightconfig.json"
                "setup.py"
                "requirements.txt"
                ".git"
              ];
              settings.basedpyright.analysis = {
                autoSearchPaths = true;
                diagnosticMode = "openFilesOnly";
                useLibraryCodeForTypes = true;
              };
            };
            clangd = {
              command = "${pkgs.clang-tools}/bin/clangd";
              args = [
                "--background-index"
                "--clang-tidy"
                "--header-insertion=iwyu"
              ];
              fileTypes = [
                ".c"
                ".cc"
                ".cpp"
                ".cxx"
                ".h"
                ".hh"
                ".hpp"
                ".hxx"
                ".m"
                ".mm"
              ];
              rootMarkers = [
                "compile_commands.json"
                "CMakeLists.txt"
                ".clangd"
                ".clang-format"
                "Makefile"
              ];
            };
            cmake-language-server = {
              command = "${pkgs.cmake-language-server}/bin/cmake-language-server";
              args = [ ];
              fileTypes = [
                ".cmake"
                "CMakeLists.txt"
              ];
              rootMarkers = [
                "CMakeLists.txt"
                ".git"
              ];
            };
            docker-compose-language-service = {
              command = "${pkgs.docker-compose-language-service}/bin/docker-compose-langserver";
              args = [ "--stdio" ];
              fileTypes = [
                "compose.yaml"
                "compose.yml"
                "docker-compose.yaml"
                "docker-compose.yml"
                ".yaml"
                ".yml"
              ];
              rootMarkers = [
                "compose.yaml"
                "compose.yml"
                "docker-compose.yaml"
                "docker-compose.yml"
              ];
            };
            dockerls = {
              command = "${pkgs.dockerfile-language-server}/bin/docker-langserver";
              args = [ "--stdio" ];
              fileTypes = [
                ".dockerfile"
                "Dockerfile"
              ];
              rootMarkers = [
                "Dockerfile"
                ".dockerignore"
                "docker-compose.yml"
                "docker-compose.yaml"
              ];
            };
            eslint = {
              command = "${pkgs.vscode-langservers-extracted}/bin/vscode-eslint-language-server";
              args = [ "--stdio" ];
              fileTypes = [
                ".js"
                ".jsx"
                ".ts"
                ".tsx"
                ".mjs"
                ".cjs"
                ".mts"
                ".cts"
                ".vue"
              ];
              rootMarkers = [
                ".eslintrc"
                ".eslintrc.js"
                ".eslintrc.json"
                ".eslintrc.yml"
                "eslint.config.js"
                "eslint.config.mjs"
              ];
              isLinter = true;
              settings = {
                validate = "on";
                run = "onType";
              };
            };
            gopls = {
              command = "${pkgs.gopls}/bin/gopls";
              args = [ "serve" ];
              fileTypes = [
                ".go"
                ".mod"
                ".sum"
              ];
              rootMarkers = [
                "go.mod"
                "go.work"
                "go.sum"
              ];
              settings.gopls = {
                gofumpt = true;
                staticcheck = true;
                analyses = {
                  shadow = true;
                  unusedparams = true;
                };
              };
            };
            lua-language-server = {
              command = "${pkgs.lua-language-server}/bin/lua-language-server";
              args = [ ];
              fileTypes = [ ".lua" ];
              rootMarkers = [
                ".luarc.json"
                ".luarc.jsonc"
                ".luacheckrc"
                ".stylua.toml"
                "stylua.toml"
                ".git"
              ];
              settings.Lua = {
                runtime.version = "LuaJIT";
                diagnostics.globals = [ "vim" ];
                workspace.checkThirdParty = false;
                telemetry.enable = false;
              };
            };
            luau-lsp = {
              command = "${pkgs.luau-lsp}/bin/luau-lsp";
              args = [ "lsp" ];
              fileTypes = [ ".luau" ];
              rootMarkers = [
                "default.project.json"
                "aftman.toml"
                ".git"
              ];
            };
            marksman = {
              command = "${pkgs.marksman}/bin/marksman";
              args = [ "server" ];
              fileTypes = [
                ".md"
                ".mdx"
                ".markdown"
              ];
              rootMarkers = [
                ".marksman.toml"
                ".git"
              ];
              warmupTimeoutMs = 2000;
            };
            nil.disabled = true;
            nixd = {
              command = "${pkgs.nixd}/bin/nixd";
              args = [ ];
              fileTypes = [ ".nix" ];
              rootMarkers = [
                "flake.nix"
                "default.nix"
                "shell.nix"
              ];
              settings.nixd.formatting.command = [ "${pkgs.nixfmt}/bin/nixfmt" ];
            };
            pyright.disabled = true;
            qmlls = {
              command = "${pkgs.kdePackages.qtdeclarative}/bin/qmlls";
              args = [
                "-E"
                "--ignore-settings"
                "--no-cmake-calls"
              ];
              fileTypes = [ ".qml" ];
              rootMarkers = [
                "CMakeLists.txt"
                "qtquickcontrols2.conf"
                ".git"
              ];
            };
            ruff = {
              command = "${pkgs.ruff}/bin/ruff";
              args = [ "server" ];
              fileTypes = [
                ".py"
                ".pyi"
              ];
              rootMarkers = [
                "pyproject.toml"
                "ruff.toml"
                ".ruff.toml"
                ".git"
              ];
              isLinter = true;
            };
            rust-analyzer = {
              command = "${pkgs.rust-analyzer}/bin/rust-analyzer";
              args = [ ];
              fileTypes = [ ".rs" ];
              rootMarkers = [
                "Cargo.toml"
                "rust-analyzer.toml"
              ];
              initOptions = { };
              settings.rust-analyzer.checkOnSave = false;
              capabilities = {
                expandMacro = true;
                flycheck = true;
                relatedTests = true;
                runnables = true;
                ssr = true;
              };
            };
            sqls = {
              command = "${pkgs.sqls}/bin/sqls";
              args = [ ];
              fileTypes = [ ".sql" ];
              rootMarkers = [
                ".sqls.yml"
                ".git"
              ];
            };
            tailwindcss = {
              command = "${pkgs.tailwindcss-language-server}/bin/tailwindcss-language-server";
              args = [ "--stdio" ];
              fileTypes = [
                ".html"
                ".css"
                ".scss"
                ".js"
                ".jsx"
                ".ts"
                ".tsx"
                ".vue"
                ".svelte"
              ];
              rootMarkers = [
                "tailwind.config.js"
                "tailwind.config.ts"
                "tailwind.config.mjs"
                "tailwind.config.cjs"
              ];
            };
            taplo = {
              command = "${pkgs.taplo}/bin/taplo";
              args = [
                "lsp"
                "stdio"
              ];
              fileTypes = [ ".toml" ];
              rootMarkers = [
                "taplo.toml"
                ".taplo.toml"
                "Cargo.toml"
                "pyproject.toml"
              ];
            };
            texlab = {
              command = "${pkgs.texlab}/bin/texlab";
              args = [ ];
              fileTypes = [
                ".tex"
                ".bib"
                ".sty"
                ".cls"
              ];
              rootMarkers = [
                ".latexmkrc"
                "latexmkrc"
                ".texlabroot"
                "texlabroot"
                "Tectonic.toml"
              ];
            };
            tinymist = {
              command = "${pkgs.tinymist}/bin/tinymist";
              args = [ ];
              fileTypes = [ ".typ" ];
              rootMarkers = [
                "typst.toml"
                ".git"
              ];
            };
            typescript-language-server = {
              command = "${pkgs.typescript-language-server}/bin/typescript-language-server";
              args = [ "--stdio" ];
              fileTypes = [
                ".ts"
                ".tsx"
                ".js"
                ".jsx"
                ".mjs"
                ".cjs"
                ".mts"
                ".cts"
              ];
              rootMarkers = [
                "package.json"
                "tsconfig.json"
                "jsconfig.json"
              ];
              initOptions = {
                hostInfo = "omp-coding-agent";
                preferences = {
                  includeInlayFunctionParameterTypeHints = true;
                  includeInlayParameterNameHints = "all";
                  includeInlayVariableTypeHints = true;
                };
              };
            };
            vscode-css-language-server = {
              command = "${pkgs.vscode-langservers-extracted}/bin/vscode-css-language-server";
              args = [ "--stdio" ];
              fileTypes = [
                ".css"
                ".scss"
                ".sass"
                ".less"
              ];
              rootMarkers = [
                "package.json"
                ".git"
              ];
              initOptions.provideFormatter = true;
            };
            vscode-html-language-server = {
              command = "${pkgs.vscode-langservers-extracted}/bin/vscode-html-language-server";
              args = [ "--stdio" ];
              fileTypes = [
                ".html"
                ".htm"
              ];
              rootMarkers = [
                "package.json"
                ".git"
              ];
              initOptions.provideFormatter = true;
            };
            vscode-json-language-server = {
              command = "${pkgs.vscode-langservers-extracted}/bin/vscode-json-language-server";
              args = [ "--stdio" ];
              fileTypes = [
                ".json"
                ".jsonc"
                ".json5"
              ];
              rootMarkers = [
                "package.json"
                ".git"
              ];
              initOptions.provideFormatter = true;
            };
            yamlls = {
              command = "${pkgs.yaml-language-server}/bin/yaml-language-server";
              args = [ "--stdio" ];
              fileTypes = [
                ".yaml"
                ".yml"
              ];
              rootMarkers = [ ".git" ];
              settings = {
                redhat.telemetry.enabled = false;
                yaml = {
                  completion = true;
                  format.enable = true;
                  hover = true;
                  validate = true;
                };
              };
            };
          };
        }
      );

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
            install -m 0600 -o ${shellUser} -g users ${lib.escapeShellArg ompLspConfigFile} ${shellOmpLspFile}

            tmp_env="$(${pkgs.coreutils}/bin/mktemp)"
            {
              printf '%s\n' ${lib.escapeShellArg "EXA_API_KEY=${exaApiKey}"}
              printf '%s\n' ${lib.escapeShellArg "OMNIROUTE_OPENCODE_API_KEY=${opencodeApiKey}"}
              printf '%s\n' ${lib.escapeShellArg "OMNIROUTE_PI_API_KEY=${piApiKey}"}
            } > "$tmp_env"
            install -m 0600 -o ${shellUser} -g users "$tmp_env" ${shellOmpEnvFile}
            rm -f "$tmp_env"

            if [ ! -e ${shellOmpConfigFile} ]; then
              printf '{}\n' > ${shellOmpConfigFile}
            fi

            ${pkgs.yq-go}/bin/yq -i '
              .retry.provider.timeoutMs = ${toString streamFirstEventTimeoutMs} |
              .lsp.enabled = true |
              .lsp.formatOnWrite = true |
              .lsp.diagnosticsOnWrite = true |
              .lsp.diagnosticsOnEdit = true
            ' ${shellOmpConfigFile}
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

        # OMP loads ~/.omp/agent/.env after process env; keep API keys scoped to
        # that 0600 file above instead of exporting them through /etc/profile.
        # Source: https://github.com/can1357/oh-my-pi/blob/main/docs/environment-variables.md
        environment.variables.PI_STREAM_FIRST_EVENT_TIMEOUT_MS = toString streamFirstEventTimeoutMs;

        environment.systemPackages = languages.packages;

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
