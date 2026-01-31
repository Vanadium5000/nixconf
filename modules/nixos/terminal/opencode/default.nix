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

      # Modular plugin and agent configuration
      pluginsConfig = import ./_plugins.nix;
      agentsConfig = import ./_agents.nix { };

      opencode = inputs.opencode.packages.${pkgs.stdenv.hostPlatform.system}.default;

      # Model definitions for switching
      opusModel = "antigravity-claude/claude-opus-4-5-thinking";
      geminiProModel = "antigravity-gemini/gemini-3-pro-preview";

      # Default expensive model (switched via opencode-model CLI)
      expensiveModel = opusModel;

      # Generate full config with agents for a given model
      mkFullConfig = model: {
        "$schema" = "https://opencode.ai/config.json";
        agent = agentsConfig.mkAgentConfig model;
        plugin = pluginsConfig.plugins;
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

      # Config variants stored in nix store for model switching
      configVariantsDir = pkgs.runCommand "opencode-configs" { } ''
        mkdir -p $out
        cat > $out/opus.json << 'EOF'
        ${builtins.toJSON (mkFullConfig opusModel)}
        EOF
        cat > $out/gemini-pro.json << 'EOF'
        ${builtins.toJSON (mkFullConfig geminiProModel)}
        EOF
      '';

      # CLI tool to switch between configs (replaces full config.json)
      opencodeModelSwitch = pkgs.writeShellScriptBin "opencode-model" ''
        CONFIG_FILE="$HOME/.config/opencode/config.json"
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
            echo "Restart OpenCode for changes to take effect."
            ;;
          gemini|gemini-pro|pro)
            cp "$GEMINI_CONFIG" "$CONFIG_FILE"
            echo "Switched to Gemini 3 Pro Preview"
            echo "Restart OpenCode for changes to take effect."
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
            echo "Restart OpenCode for changes to take effect."
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
        # Full config with agents - defaults to opus, use `opencode-model` CLI to switch
        "${configFile}".text = builtins.toJSON (mkFullConfig expensiveModel);
        ".config/opencode/skills".source = skills.skillsSource + "/skill";
        ".config/opencode/AGENTS.md".source = ./AGENTS.md;
        # Agent prompts - referenced via {file:./prompts/*.md} in config
        ".config/opencode/prompts".source = ./prompts;
      };
    };
}
