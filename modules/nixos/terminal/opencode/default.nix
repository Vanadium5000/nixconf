{ inputs, self, ... }:
{
  flake.nixosModules.opencode =
    {
      pkgs,
      config,
      ...
    }:
    let
      user = config.preferences.user.username;
      languages = import ./_languages.nix { inherit pkgs self; };
      providers = import ./_providers.nix { inherit self; };
      skills = import ./_skills.nix { inherit pkgs; };

      opencode = inputs.opencode.packages.${pkgs.stdenv.hostPlatform.system}.default;

      # Model definitions for switching
      opusModel = "antigravity-claude/claude-opus-4-5-thinking";
      geminiProModel = "antigravity-gemini/gemini-3-pro-preview";

      # Base oh-my-opencode config as a function of the "expensive" model
      # Note: Comments are not included in JSON output, but preserved here for documentation
      mkOhMyOpencodeConfig = expensiveModel: {
        "$schema" =
          "https://raw.githubusercontent.com/code-yeongyu/oh-my-opencode/master/assets/oh-my-opencode.schema.json";
        "google_auth" = false; # Disable conflicts
        # Disable oh-my-opencode's default websearch_exa - replaced with full Exa MCP in config.json
        "disabled_mcps" = [ "websearch" ];

        # Oh-My-OpenCode provides 10 specialized AI agents. Each has distinct expertise, optimized models, and tool permissions.
        # Docs: https://github.com/code-yeongyu/oh-my-opencode/blob/dev/docs/features.md
        "agents" = {
          "oracle" = {
            "model" = expensiveModel;
          };
          "librarian" = {
            "model" = "antigravity-gemini/gemini-3-flash";
          };
          "explore" = {
            "model" = "antigravity-gemini/gemini-3-flash";
          };
          "multimodal-looker" = {
            "model" = "antigravity-gemini/gemini-3-flash";
          };

          # Main Agents
          "atlas" = {
            "model" = expensiveModel; # Maybe a tad excessive
          };
          "prometheus" = {
            "model" = expensiveModel;
          };
          # Plan Consultant
          "metis" = {
            "model" = expensiveModel;
          };
          # Plan Reviewer
          "momus" = {
            "model" = expensiveModel;
          };
          "sisyphus" = {
            "model" = expensiveModel;
          };
          # Worker
          "sisyphus-junior" = {
            "model" = "antigravity-gemini/gemini-3-flash";
          };

          # Advisor - read-only conversational agent for questions & intuitive feedback
          "advisor" = {
            "model" = expensiveModel;
            "description" = "Read-only advisor for questions, feedback, and discussion on any topic";
            "disable" = false;
            "tools" = {
              # Disable all write/edit tools - read-only agent
              "Write" = false;
              "Edit" = false;
              "Bash" = false;
              "todowrite" = false;
              "delegate_task" = false;
              "task" = false;
              "interactive_bash" = false;
            };
            "prompt_append" = ''
              You are Advisor - a thoughtful conversational partner.

              YOUR ROLE:
              - Answer questions on ANY topic (code-related or not)
              - Provide intuitive feedback, opinions, and insights
              - Engage in philosophical, creative, or technical discussions
              - Help think through problems without necessarily solving them in code

              CONSTRAINTS:
              - You CANNOT edit files, run commands, or make changes
              - You CAN read files and search the codebase for context
              - Focus on understanding, explaining, and advising

              STYLE:
              - Be direct and genuine
              - Share nuanced perspectives
              - It's okay to say "I don't know" or "I'm uncertain"
              - Engage with the human's actual question, not what you think they should ask
            '';
          };
        };
        # Override category models (used by delegate_task)
        # Docs: https://github.com/code-yeongyu/oh-my-opencode/blob/dev/docs/category-skill-guide.md
        "categories" = {
          # Trivial tasks - single file changes, typo fixes, simple modifications
          "quick" = {
            "model" = "opencode/gpt-5-nano";
          };
          # Frontend, UI/UX, design, styling, animation
          "visual-engineering" = {
            "model" = "antigravity-gemini/gemini-3-pro-preview";
          };
          # Deep logical reasoning, complex architecture decisions requiring extensive analysis
          "ultrabrain" = {
            "model" = expensiveModel;
          };
          # Highly creative/artistic tasks, novel ideas
          "artistry" = {
            "model" = expensiveModel;
          };
          # Tasks that don't fit other categories, low effort required
          "unspecified-low" = {
            "model" = "antigravity-gemini/gemini-3-flash";
          };
          # Tasks that don't fit other categories, high effort required
          "unspecified-high" = {
            "model" = expensiveModel;
          };
          # Documentation, prose, technical writing
          "writing" = {
            "model" = "antigravity-gemini/gemini-3-pro-preview";
          };
        };
      };

      # Generate both config variants
      opusConfig = builtins.toJSON (mkOhMyOpencodeConfig opusModel);
      geminiProConfig = builtins.toJSON (mkOhMyOpencodeConfig geminiProModel);

      # Config variants stored in nix store
      configVariantsDir = pkgs.runCommand "opencode-model-configs" { } ''
        mkdir -p $out
        cat > $out/opus.json << 'EOF'
        ${opusConfig}
        EOF
        cat > $out/gemini-pro.json << 'EOF'
        ${geminiProConfig}
        EOF
      '';

      # CLI tool to switch between configs
      opencodeModelSwitch = pkgs.writeShellScriptBin "opencode-model" ''
        CONFIG_FILE="$HOME/.config/opencode/oh-my-opencode.json"
        OPUS_CONFIG="${configVariantsDir}/opus.json"
        GEMINI_CONFIG="${configVariantsDir}/gemini-pro.json"

        get_current() {
          if [ -f "$CONFIG_FILE" ]; then
            if grep -q "claude-opus-4-5-thinking" "$CONFIG_FILE" 2>/dev/null; then
              echo "opus"
            else
              echo "gemini-pro"
            fi
          else
            echo "unknown"
          fi
        }

        case "''${1:-}" in
          opus)
            cp "$OPUS_CONFIG" "$CONFIG_FILE"
            echo "Switched to Claude Opus 4.5 Thinking"
            ;;
          gemini|gemini-pro|pro)
            cp "$GEMINI_CONFIG" "$CONFIG_FILE"
            echo "Switched to Gemini 3 Pro Preview"
            ;;
          status|"")
            current=$(get_current)
            echo "Current model: $current"
            ;;
          toggle)
            current=$(get_current)
            if [ "$current" = "opus" ]; then
              cp "$GEMINI_CONFIG" "$CONFIG_FILE"
              echo "Switched to Gemini 3 Pro Preview"
            else
              cp "$OPUS_CONFIG" "$CONFIG_FILE"
              echo "Switched to Claude Opus 4.5 Thinking"
            fi
            ;;
          *)
            echo "Usage: opencode-model [opus|gemini-pro|toggle|status]"
            echo ""
            echo "Commands:"
            echo "  opus       Switch to Claude Opus 4.5 Thinking (expensive)"
            echo "  gemini-pro Switch to Gemini 3 Pro Preview (cheaper)"
            echo "  toggle     Toggle between opus and gemini-pro"
            echo "  status     Show current model (default)"
            exit 1
            ;;
        esac
      '';

      ohmyopencodeConfigFile = ".config/opencode/oh-my-opencode.json";

      opencodeEnv = pkgs.buildEnv {
        name = "opencode-env";
        paths = languages.packages ++ skills.packages;
      };

      opencodeInitScript = pkgs.writeShellScript "opencode-init" ''
        mkdir -p "$HOME/.local/cache/opencode/node_modules/@opencode-ai"
        mkdir -p "$HOME/.config/opencode/node_modules/@opencode-ai"
        if [ -d "$HOME/.config/opencode/node_modules/@opencode-ai/plugin" ]; then
          if [ ! -L "$HOME/.local/cache/opencode/node_modules/@opencode-ai/plugin" ]; then
            ln -sf "$HOME/.config/opencode/node_modules/@opencode-ai/plugin" \
                   "$HOME/.local/cache/opencode/node_modules/@opencode-ai/plugin"
          fi
        fi
        exec ${opencode}/bin/opencode "$@"
      '';

      opencodeWrapped =
        pkgs.runCommand "opencode-wrapped"
          {
            buildInputs = [ pkgs.makeWrapper ];
          }
          ''
            mkdir -p $out/bin
            makeWrapper ${opencodeInitScript} $out/bin/opencode \
              --prefix PATH : ${opencodeEnv}/bin \
              --set OPENCODE_LIBC ${pkgs.glibc}/lib/libc.so.6
          '';
      configFile = ".config/opencode/config.json";

      # Persistence configuration using bind mount for reliability
      toolsPersistence = self.lib.persistence.mkPersistent {
        method = "bind";
        inherit user;
        fileName = "antigravity_tools";
        targetFile = "/home/${user}/.antigravity_tools";
        isDirectory = true;
      };
    in
    {
      environment.systemPackages = [
        opencodeWrapped
        opencodeModelSwitch
      ]
      ++ languages.packages;

      # Setup script to ensure files exist before mount
      system.activationScripts.opencode-persistence = {
        text = toolsPersistence.activationScript;
        deps = [ "users" ];
      };

      # Bind mount for reliable persistence (apps can't overwrite)
      fileSystems = toolsPersistence.fileSystems;
      hjem.users.${user}.files = {
        "${configFile}".text = builtins.toJSON {
          "$schema" = "https://opencode.ai/config.json";
          plugin = [
            # "opencode-antigravity-auth@latest"
            "@mohak34/opencode-notifier@latest"
            "oh-my-opencode@latest"
            # "@tarquinen/opencode-dcp@latest"
          ];
          small_model = "opencode/gpt-5-nano";
          autoupdate = false;
          share = "disabled";
          permission = {
            read = {
              # Don't allow the AI to read *.redacted.*, e.g. .../script.redacted.ts
              "*.redacted.*" = "deny";
            };
          };
          disabled_providers = [
            "amazon-bedrock"
            "anthropic"
            "azure-openai"
            "azure-cognitive-services"
            "baseten"
            "cerebras"
            "cloudflare-ai-gateway"
            "cortecs"
            "deepseek"
            "deep-infra"
            "fireworks-ai"
            "github-copilot"
            "google-vertex-ai"
            "groq"
            "hugging-face"
            "helicone"
            "llama.cpp"
            "io-net"
            "lmstudio"
            "moonshot-ai"
            "nebius-token-factory"
            "ollama"
            "ollama-cloud"
            "openai"
            "sap-ai-core"
            "ovhcloud-ai-endpoints"
            "together-ai"
            "venice-ai"
            "xai"
            "zai"
            "zenmux"
          ];
          enabled_providers = [
            "opencode"
            "antigravity-gemini"
            "antigravity-claude"
          ];
          mcp = {
            gh_grep = {
              type = "remote";
              url = "https://mcp.grep.app/";
              enabled = true;
              timeout = 10000;
            };
            deepwiki = {
              type = "remote";
              url = "https://mcp.deepwiki.com/mcp";
              enabled = true;
              timeout = 10000;
            };
            context7 = {
              type = "remote";
              url = "https://mcp.context7.com/mcp";
              enabled = true;
              timeout = 10000;
            };
            daisyui = {
              type = "local";
              command = [ "${self.packages.${pkgs.stdenv.hostPlatform.system}.daisyui-mcp}/bin/daisyui-mcp" ];
              enabled = true;
              timeout = 10000;
            };
            playwrite = {
              enabled = true;
              type = "local";
              command = [
                "${pkgs.playwright-mcp}/bin/mcp-server-playwright"
                "--browser=firefox"
                "--headless"
              ];
            };
            markdown_lint = {
              type = "local";
              command = [
                "${inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.markdown-lint-mcp}/bin/markdown-lint-mcp"
              ];
              enabled = true;
              timeout = 10000;
            };
            qmllint = {
              type = "local";
              command = [
                "${inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.qmllint-mcp}/bin/qmllint-mcp"
              ];
              enabled = true;
              timeout = 10000;
            };
            quickshell = {
              type = "local";
              command = [
                "${
                  inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.quickshell-docs-mcp
                }/bin/quickshell-docs-mcp"
              ];
              enabled = true;
              timeout = 10000;
            };
            # Exa MCP - high-quality parallel web search with deep research capabilities
            websearch = {
              type = "remote";
              url = "https://mcp.exa.ai/mcp?exaApiKey=${self.secrets.EXA_API_KEY}&tools=web_search_exa,deep_search_exa,get_code_context_exa,crawling_exa,deep_researcher_start,deep_researcher_check";
              enabled = true;
              timeout = 30000; # 30s for deep searches
            };
          };
          formatter = languages.formatter;
          lsp = languages.lsp;
          provider = providers.config;
        };
        ".config/opencode/skills".source = skills.skillsSource + "/skill";
        ".config/opencode/AGENTS.md".source = ./AGENTS.md;

        # oh-my-opencode config - defaults to opus, use `opencode-model` CLI to switch
        "${ohmyopencodeConfigFile}".text = opusConfig;
      };
    };
}
