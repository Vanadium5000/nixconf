{ inputs, self, ... }:
{
  flake.nixosModules.opencode =
    {
      pkgs,
      config,
      lib,
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

      # Model definitions for switching — change these to update everything automatically
      opusModel = "antigravity-claude/claude-opus-4-6-thinking";
      geminiProModel = "antigravity-gemini/gemini-3.1-pro-high";

      # Derive human-readable names from provider config
      modelName =
        model:
        let
          parts = builtins.split "/" model;
          providerId = builtins.elemAt parts 0;
          modelId = builtins.elemAt parts 2;
        in
        providers.config.${providerId}.models.${modelId}.name;

      opusName = modelName opusModel;
      geminiProName = modelName geminiProModel;

      # Dynamic image model detection - finds first model with "image" in output modalities
      # This avoids hardcoding model names that change frequently
      imageModel =
        let
          # Helper to check if a model supports image output
          isImageModel =
            providerId: modelId: model:
            builtins.elem "image" (model.modalities.output or [ ]);

          # Flatten providers into a list of { id, modelId, model }
          allModels = lib.flatten (
            lib.mapAttrsToList (
              providerId: provider:
              lib.mapAttrsToList (modelId: model: {
                id = "${providerId}/${modelId}";
                inherit providerId modelId model;
              }) provider.models
            ) providers.config
          );

          # Find the first one that matches
          firstImageModel = lib.findFirst (m: isImageModel m.providerId m.modelId m.model) null allModels;
        in
        if firstImageModel != null then firstImageModel.id else "unknown/unknown";

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
            timeout = 20000;
          };
          context7 = {
            type = "remote";
            url = "https://mcp.context7.com/mcp";
            enabled = true;
            timeout = 20000;
          };
          daisyui = {
            type = "local";
            command = [ "${self.packages.${pkgs.stdenv.hostPlatform.system}.daisyui-mcp}/bin/daisyui-mcp" ];
            enabled = false;
            timeout = 20000;
          };
          playwrite = {
            enabled = false;
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
            enabled = false;
            timeout = 20000;
          };
          quickshell = {
            type = "local";
            command = [
              "${
                inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.quickshell-docs-mcp
              }/bin/quickshell-docs-mcp"
            ];
            enabled = false;
            timeout = 20000;
          };
          # Exa MCP - high-quality parallel web search with deep research capabilities
          websearch = {
            type = "remote";
            url = "https://mcp.exa.ai/mcp?exaApiKey=${self.secrets.EXA_API_KEY}&tools=web_search_exa,deep_search_exa,get_code_context_exa,crawling_exa,deep_researcher_start,deep_researcher_check";
            enabled = true;
            timeout = 30000; # 30s for deep searches
          };
          # PowerPoint MCP - create/edit presentations using python-pptx
          # Supports creating and manipulating pptx files programmatically
          powerpoint = {
            type = "local";
            command = [
              "${self.packages.${pkgs.stdenv.hostPlatform.system}.powerpoint-mcp}/bin/ppt_mcp_server"
            ];
            enabled = false;
            timeout = 30000;
          };
          # Image Generation MCP - generates images using the first available image model
          image_gen = {
            type = "local";
            command = [
              "${pkgs.bun}/bin/bun"
              "${/home/matrix/nixconf/modules/nixos/scripts/bunjs/mcp/image-gen.ts}"
            ];
            enabled = true;
            timeout = 60000; # Image generation can take a while
            env = {
              CLIPROXYAPI_KEY = self.secrets.CLIPROXYAPI_KEY;
              IMAGE_MODEL = imageModel;
            };
          };
          # Slide Preview MCP - converts presentation slides to images for previewing
          slide_preview = {
            type = "local";
            command = [
              "${pkgs.bun}/bin/bun"
              "${/home/matrix/nixconf/modules/nixos/scripts/bunjs/mcp/slide-preview.ts}"
            ];
            enabled = false;
            timeout = 30000;
          };
        };

        inherit (languages) formatter;
        inherit (languages) lsp;
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
      opencodeModelSwitch = pkgs.writeShellScriptBin "opencode-models" ''
                                                # Global config path
                                        GLOBAL_CONFIG_FILE="$HOME/.config/opencode/config.json"
                                        
                                        # Local config paths
                                        LOCAL_JSONC_FILE="$PWD/opencode.jsonc"
                                        
                                        OPUS_CONFIG="${configVariantsDir}/opus.json"
                                        GEMINI_CONFIG="${configVariantsDir}/gemini-pro.json"
                                        JQ="${pkgs.jq}/bin/jq"
                                        GUM="${pkgs.gum}/bin/gum"

                                                update_model_in_config() {
                                                  local target_config="$1"
                                                  
                                                  if [ -f "$GLOBAL_CONFIG_FILE" ]; then
                                                    # Patch existing global config with new model settings, preserving MCPs
                                                    local temp_file=$(mktemp)
                                                    
                                                    # Merge .agent, .provider, and .small_model from target_config into existing config
                                                    $JQ '.agent = $target[0].agent | .provider = $target[0].provider | .small_model = $target[0].small_model' \
                                                      --slurpfile target "$target_config" "$GLOBAL_CONFIG_FILE" > "$temp_file" && mv "$temp_file" "$GLOBAL_CONFIG_FILE"
                                                  else
                                                    # No existing config, just copy the target
                                                    cp "$target_config" "$GLOBAL_CONFIG_FILE"
                                                    chmod 644 "$GLOBAL_CONFIG_FILE"
                                                  fi
                                                }

                                                get_current() {
                                                  if [ -f "$GLOBAL_CONFIG_FILE" ]; then
                                                    local current_model=$($JQ -r '.agent.build.model // empty' "$GLOBAL_CONFIG_FILE" 2>/dev/null)
                                                    if [ "$current_model" = "${opusModel}" ]; then
                                                      echo "opus"
                                                    elif [ "$current_model" = "${geminiProModel}" ]; then
                                                      echo "gemini-pro"
                                                    else
                                                      echo "unknown"
                                                    fi
                                                  else
                                                    echo "unknown"
                                                  fi
                                                }

                                        init_project() {
                                          local choice
                                           choice=$($GUM choose "Web Development" "NixOS Config" "PowerPoint/Office Work" "All MCPs" "No MCPs" "Custom MCP File" --header "📦 Select Project Template (initializes in $PWD)" --cursor="▶ " --selected.foreground="212" --cursor.foreground="212")

                                           if [ -z "$choice" ]; then
                                             echo "Operation cancelled."
                                             return 1
                                           fi
                                           
                                           # Check for existing manual configs to warn the user
                                           if [ -f "$LOCAL_JSONC_FILE" ] || [ -f "$PWD/.opencode/config.json" ]; then
                                             if ! $GUM confirm "This will overwrite your existing opencode.jsonc. Continue?"; then
                                               echo "Operation cancelled."
                                               return 1
                                             fi
                                           fi

                                           local temp_file=$(mktemp)
                                           
                                  case "$choice" in
                                     "Web Development")
                                        cat << 'JSONC' > "$LOCAL_JSONC_FILE"
         {
           "mcp": {
             "daisyui": { "enabled": true },
             "playwrite": { "enabled": true },
             "websearch": { "enabled": true },
             "context7": { "enabled": true },
             "gh_grep": { "enabled": true },
             "image_gen": { "enabled": true }
             // "quickshell": { "enabled": false },
             // "qmllint": { "enabled": false },
             // "powerpoint": { "enabled": false },
             // "slide_preview": { "enabled": false }
           }
         }
         JSONC
                                       ;;
                                     "NixOS Config")
                                        cat << 'JSONC' > "$LOCAL_JSONC_FILE"
         {
           "mcp": {
             "quickshell": { "enabled": true },
             "qmllint": { "enabled": true },
             "websearch": { "enabled": true },
             "gh_grep": { "enabled": true },
             "image_gen": { "enabled": true }
             // "daisyui": { "enabled": false },
             // "playwrite": { "enabled": false },
             // "context7": { "enabled": false },
             // "powerpoint": { "enabled": false },
             // "slide_preview": { "enabled": false }
           }
         }
         JSONC
                                       ;;
                                     "PowerPoint/Office Work")
                                        cat << 'JSONC' > "$LOCAL_JSONC_FILE"
         {
           "mcp": {
             "powerpoint": { "enabled": true },
             "slide_preview": { "enabled": true },
             "websearch": { "enabled": true },
             "gh_grep": { "enabled": true },
             "image_gen": { "enabled": true }
             // "daisyui": { "enabled": false },
             // "playwrite": { "enabled": false },
             // "context7": { "enabled": false },
             // "quickshell": { "enabled": false },
             // "qmllint": { "enabled": false }
           }
         }
         JSONC
                                        ;;
                                     "All MCPs")
                                        cat << 'JSONC' > "$LOCAL_JSONC_FILE"
         {
           "mcp": {
             "daisyui": { "enabled": true },
             "playwrite": { "enabled": true },
             "websearch": { "enabled": true },
             "context7": { "enabled": true },
             "gh_grep": { "enabled": true },
             "quickshell": { "enabled": true },
             "qmllint": { "enabled": true },
             "powerpoint": { "enabled": true },
             "image_gen": { "enabled": true },
             "slide_preview": { "enabled": true }
           }
         }
         JSONC
                                       ;;

                                    "No MCPs")
                                       cat << 'JSONC' > "$LOCAL_JSONC_FILE"
        {
          "mcp": {
            // "daisyui": { "enabled": false },
            // "playwrite": { "enabled": false },
            // "websearch": { "enabled": false },
            // "context7": { "enabled": false },
            // "gh_grep": { "enabled": false },
            // "quickshell": { "enabled": false },
            // "qmllint": { "enabled": false },
            // "powerpoint": { "enabled": false }
          }
        }
        JSONC
                                       ;;
                                    "Custom MCP File")
                                       cat << 'JSONC' > "$LOCAL_JSONC_FILE"
        {
          "mcp": {
            // "daisyui": { "enabled": false },
            // "playwrite": { "enabled": false },
            "websearch": { "enabled": true },
            "context7": { "enabled": true },
            "gh_grep": { "enabled": true }
            // "quickshell": { "enabled": false },
            // "qmllint": { "enabled": false },
            // "powerpoint": { "enabled": false }
          }
        }
        JSONC
                                       ;;
                                  esac
                                  
                                  $GUM style --foreground 212 "Created opencode.jsonc! Edit this file to toggle specific MCPs for this project."
                                  
                                  # Create a nice message using gum
                                  $GUM style \
                                    --foreground 212 --border-foreground 212 --border double \
                                    --align center --width 50 --margin "1 2" --padding "1 2" \
                                    "✨ Project Initialized ✨" "Template: $choice" "Saved to: opencode.jsonc"
                                }
                                        
                                        tui_menu() {
                                                  local context_msg="Context: Global"
                                                  if [ -f "$LOCAL_JSONC_FILE" ]; then
                                                    context_msg="Context: Local Project ($LOCAL_JSONC_FILE)"
                                                  fi
                                                  
                                                  local current_model=$(get_current)
                                                  local model_disp="Unknown"
                                                  if [ "$current_model" = "opus" ]; then
                                                    model_disp="${opusName}"
                                                  elif [ "$current_model" = "gemini-pro" ]; then
                                                    model_disp="${geminiProName}"
                                                  fi
                                                  
                                                  local action
                                                  action=$($GUM choose \
                                                    "Init Project MCPs (Current Dir)" \
                                                    "Switch to Opus (Expensive)" \
                                                    "Switch to Gemini Pro (Cheaper)" \
                                                    "Toggle Model" \
                                                    "Exit" \
                                                    --header "🤖 OpenCode Configuration Manager
                                        $context_msg
                                        Current Model: $model_disp
                                        " \
                                                    --cursor="▶ " --selected.foreground="212" --cursor.foreground="212")
                                                    
                                                  case "$action" in
                                                    "Init Project MCPs (Current Dir)")
                                                      init_project
                                                      ;;
                                                    "Switch to Opus (Expensive)")
                                                      update_model_in_config "$OPUS_CONFIG"
                                                      $GUM style --foreground 212 "✅ Switched to ${opusName} (Global)"
                                                      ;;
                                                    "Switch to Gemini Pro (Cheaper)")
                                                      update_model_in_config "$GEMINI_CONFIG"
                                                      $GUM style --foreground 212 "✅ Switched to ${geminiProName} (Global)"
                                                      ;;
                                                    "Toggle Model")
                                                      if [ "$current_model" = "opus" ]; then
                                                        update_model_in_config "$GEMINI_CONFIG"
                                                        $GUM style --foreground 212 "✅ Switched to ${geminiProName} (Global)"
                                                      else
                                                        update_model_in_config "$OPUS_CONFIG"
                                                        $GUM style --foreground 212 "✅ Switched to ${opusName} (Global)"
                                                      fi
                                                      ;;
                                                    *)
                                                      exit 0
                                                      ;;
                                                  esac
                                                }

                                                # If no arguments provided, open the TUI
                                                if [ $# -eq 0 ]; then
                                                  tui_menu
                                                  exit 0
                                                fi

                                                case "''${1:-}" in
                                                  opus)
                                                    update_model_in_config "$OPUS_CONFIG"
                                                    echo "Switched to ${opusName}"
                                                    ;;
                                                  gemini|gemini-pro|pro)
                                                    update_model_in_config "$GEMINI_CONFIG"
                                                    echo "Switched to ${geminiProName}"
                                                    ;;
                                                  init)
                                                    init_project
                                                    ;;
                                                  status)
                                                    current=$(get_current)
                                                    if [ -f "$LOCAL_JSONC_FILE" ]; then
                                                      echo "Context: Local ($LOCAL_JSONC_FILE)"
                                                    else
                                                      echo "Context: Global"
                                                    fi
                                                    echo "Current model: $current"
                                                    ;;
                                                  toggle)
                                                    current=$(get_current)
                                                    if [ "$current" = "opus" ]; then
                                                      update_model_in_config "$GEMINI_CONFIG"
                                                      echo "Switched to ${geminiProName}"
                                                    else
                                                      update_model_in_config "$OPUS_CONFIG"
                                                      echo "Switched to ${opusName}"
                                                    fi
                                                    ;;
                                                  *)
                                                    echo "Usage: opencode-models [opus|gemini-pro|toggle|status|init]"
                                                    echo ""
                                                    echo "Run without arguments to open the interactive UI."
                                                    echo ""
                                                    echo "Commands:"
                                                    echo "  init       Initialize project MCPs in current directory"
                                                    echo "  opus       Switch to ${opusName} (expensive)"
                                                    echo "  gemini-pro Switch to ${geminiProName} (cheaper)"
                                                    echo "  toggle     Toggle between opus and gemini-pro"
                                                    echo "  status     Show current model and context"
                                                    exit 1
                                                    ;;
                                                esac
      '';

      opencodeEnv = pkgs.buildEnv {
        name = "opencode-env";
        paths = languages.packages ++ skills.packages ++ [ pkgs.libreoffice ];
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

      # Persist opencode state (sessions, history, etc.)
      opencodePersistence = self.lib.persistence.mkPersistent {
        method = "bind";
        inherit user;
        fileName = "opencode";
        targetFile = "/home/${user}/.local/share/opencode";
        isDirectory = true;
      };

      # Persist opencode-agent-memory data (Letta-style memory blocks)
      opencodeMemoryPersistence = self.lib.persistence.mkPersistent {
        method = "bind";
        inherit user;
        fileName = "opencode-memory";
        targetFile = "/home/${user}/.opencode/memory";
        isDirectory = true;
      };

      # Persist planning system state (plans, review status, annotations)
      opencodePlansPersistence = self.lib.persistence.mkPersistent {
        method = "bind";
        inherit user;
        fileName = "opencode-plans";
        targetFile = "/home/${user}/.opencode/plans";
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
        text =
          toolsPersistence.activationScript
          + opencodePersistence.activationScript
          + opencodeMemoryPersistence.activationScript
          + opencodePlansPersistence.activationScript;
        deps = [ "users" ];
      };

      # Bind mount for reliable persistence (apps can't overwrite)
      fileSystems =
        toolsPersistence.fileSystems
        // opencodePersistence.fileSystems
        // opencodeMemoryPersistence.fileSystems
        // opencodePlansPersistence.fileSystems;
      hjem.users.${user}.files = {
        # Full config with agents - defaults to opus, use `opencode-model` CLI to switch
        "${configFile}".text = builtins.toJSON (mkFullConfig expensiveModel);
        # Skills (AI-loadable instructions) - note: "skill" not "skills"
        ".config/opencode/skill".source = skills.skillsSource + "/skill";
        # Commands (slash command definitions)
        ".config/opencode/command".source = skills.commandsSource + "/command";
        ".config/opencode/AGENTS.md".source = ./AGENTS.md;
        # Agent prompts - referenced via {file:./prompts/*.md} in config
        ".config/opencode/prompts".source = ./prompts;
      };
    };
}
