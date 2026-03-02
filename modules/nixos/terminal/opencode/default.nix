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
      pluginsConfig = import ./_plugins.nix;
      agentsConfig = import ./_agents.nix { };

      inherit (pkgs.unstable) opencode;

      # Define the available models mapping
      models = {
        "gemini-3.1-pro-high" = "antigravity-gemini/gemini-3.1-pro-high";
        "claude-opus" = "antigravity-claude/claude-opus-4-6-thinking";
        "gemini-3-flash" = "antigravity-gemini/gemini-3-flash";
        "gemini-3.1-flash-image" = "antigravity-gemini/gemini-3.1-flash-image";
        "kimi-2.5" = "kilo-code/moonshotai/kimi-k2.5:free";
        "minimax-2.5" = "opencode/minimax-m2.5-free";
      };

      # MCP server configuration shared between configs and project templates
      mcpConfig = {
        # Remote tool: Fast AST-based regex search over public GitHub repositories
        gh_grep = {
          type = "remote";
          url = "https://mcp.grep.app/";
          enabled = true;
          timeout = 20000;
        };
        # Remote tool: Advanced documentation index, useful for looking up up-to-date APIs
        context7 = {
          type = "remote";
          url = "https://mcp.context7.com/mcp";
          enabled = true;
          timeout = 20000;
        };
        # Local tool: Manage UI components using DaisyUI schemas
        daisyui = {
          type = "local";
          command = [ "${self.packages.${pkgs.stdenv.hostPlatform.system}.daisyui-mcp}/bin/daisyui-mcp" ];
          enabled = false;
          timeout = 20000;
        };
        # Local tool: Headless browser automation and end-to-end testing
        playwrite = {
          enabled = false;
          type = "local";
          command = [
            "${pkgs.playwright-mcp}/bin/mcp-server-playwright"
            "--browser=firefox"
            "--headless"
          ];
        };
        # Local tool: Lints markdown files to ensure compliance with format standards
        markdown_lint = {
          type = "local";
          command = [
            "${inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.markdown-lint-mcp}/bin/markdown-lint-mcp"
          ];
          enabled = true;
          timeout = 10000;
        };
        # Local tool: Validates Qt/QML syntax for NixOS widget configurations
        qmllint = {
          type = "local";
          command = [
            "${inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.qmllint-mcp}/bin/qmllint-mcp"
          ];
          enabled = false;
          timeout = 20000;
        };
        # Local tool: Reads documentation for the custom Quickshell UI compositor
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
        # Remote tool: High-quality parallel web search with deep research capabilities
        websearch = {
          type = "remote";
          url = "https://mcp.exa.ai/mcp?exaApiKey=${self.secrets.EXA_API_KEY}&tools=web_search_exa,deep_search_exa,get_code_context_exa,crawling_exa,deep_researcher_start,deep_researcher_check";
          enabled = true;
          timeout = 30000;
        };
        # Local tool: Create and manipulate PowerPoint presentations programmatically
        powerpoint = {
          type = "local";
          command = [
            "${self.packages.${pkgs.stdenv.hostPlatform.system}.powerpoint-mcp}/bin/ppt_mcp_server"
          ];
          enabled = false;
          timeout = 30000;
        };
        # Local tool: Generates images via the primary image-capable model
        image_gen = {
          type = "local";
          command = [
            "${pkgs.writeShellScript "image-gen-mcp-wrapper" ''
              export CLIPROXYAPI_KEY="${self.secrets.CLIPROXYAPI_KEY}"
              export IMAGE_MODEL="${models."gemini-3.1-flash-image"}"
              exec ${pkgs.bun}/bin/bun ${/home/matrix/nixconf/modules/nixos/scripts/bunjs/mcp/image-gen.ts}
            ''}"
          ];
          enabled = true;
          timeout = 60000;
        };
        # Local tool: Renders presentation slides to images for visual previewing
        slide_preview = {
          type = "local";
          command = [
            "${pkgs.writeShellScript "slide-preview-mcp-wrapper" ''
              export PATH="${
                pkgs.lib.makeBinPath [
                  pkgs.libreoffice
                  pkgs.poppler-utils
                ]
              }:$PATH"
              exec ${pkgs.bun}/bin/bun ${/home/matrix/nixconf/modules/nixos/scripts/bunjs/mcp/slide-preview.ts}
            ''}"
          ];
          enabled = false;
          timeout = 30000;
        };
      };

      # Base configuration containing non-dynamic parts
      baseConfig = {
        "$schema" = "https://opencode.ai/config.json";
        plugin = pluginsConfig.plugins;
        small_model = "opencode/gpt-5-nano";
        autoupdate = false;
        share = "disabled";
        permission = {
          read = {
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
          "kilo-code"
        ];
        mcp = mcpConfig;
        inherit (languages) formatter lsp;
        provider = providers.config;
      };

      # Generate initial fallback config so opencode has *something* to launch with if modified
      initialConfig = baseConfig // {
        agent = agentsConfig.mkAgentConfig {
          advancedModel = models."gemini-3.1-pro-high";
          mediumModel = models."gemini-3-flash";
          fastModel = models."minimax-2.5";
        };
      };

      # Define project MCP templates
      mcpTemplates =
        let
          mkTemplate = enabled: {
            mcp = lib.genAttrs enabled (name: {
              inherit (mcpConfig.${name}) enabled;
            });
          };
          allMcpNames = lib.attrNames mcpConfig;
        in
        {
          "Web Development" = mkTemplate [
            "daisyui"
            "playwrite"
            "websearch"
            "context7"
            "gh_grep"
            "image_gen"
          ];
          "NixOS Config" = mkTemplate [
            "quickshell"
            "qmllint"
            "websearch"
            "gh_grep"
            "image_gen"
          ];
          "PowerPoint/Office Work" = mkTemplate [
            "powerpoint"
            "slide_preview"
            "websearch"
            "gh_grep"
            "image_gen"
          ];
          "All MCPs" = mkTemplate allMcpNames;
          "No MCPs" = {
            mcp = { };
          };
          "Custom MCP File" = mkTemplate [
            "websearch"
            "context7"
            "gh_grep"
          ];
        };

      # Store templates in the Nix store for rapid switching
      configVariantsDir = pkgs.runCommand "opencode-configs" { } ''
        mkdir -p $out/templates
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (
            name: value:
            let
              safeName = lib.replaceStrings [ " " "/" ] [ "_" "_" ] name;
            in
            ''
              cat > "$out/templates/${safeName}.json" << 'EOF'
              ${builtins.toJSON value}
              EOF
            ''
          ) mcpTemplates
        )}
      '';

      # TUI for model/profile and template switching
      opencodeModelSwitch = pkgs.writeShellScriptBin "opencode-models" ''
                GLOBAL_CONFIG_FILE="$HOME/.config/opencode/config.json"
                LOCAL_JSONC_FILE="$PWD/opencode.jsonc"
                TEMPLATES_DIR="${configVariantsDir}/templates"
                JQ="${pkgs.jq}/bin/jq"
                GUM="${pkgs.gum}/bin/gum"

                # Safe extraction without subshells breaking syntax
                get_current() {
                  local agent_key="$1"
                  if [ -f "$GLOBAL_CONFIG_FILE" ]; then
                    if [ "$agent_key" = "advanced" ]; then
                       $JQ -r '.agent.build.model // empty' "$GLOBAL_CONFIG_FILE" 2>/dev/null
                    elif [ "$agent_key" = "medium" ]; then
                       $JQ -r '.agent.researcher.model // empty' "$GLOBAL_CONFIG_FILE" 2>/dev/null
                    elif [ "$agent_key" = "fast" ]; then
                       $JQ -r '.agent.scout.model // empty' "$GLOBAL_CONFIG_FILE" 2>/dev/null
                    fi
                  else
                    echo "unknown"
                  fi
                }

                update_model_in_config() {
                  local agent_key="$1"
                  local new_model="$2"

                  if [ -f "$GLOBAL_CONFIG_FILE" ]; then
                    local temp_file=$(mktemp)
                    
                    # Map the agents that use the selected category
                    if [ "$agent_key" = "advanced" ]; then
                      $JQ ".agent.build.model = \"$new_model\" | .agent.plan.model = \"$new_model\" | .agent[\"plan-reviewer\"].model = \"$new_model\" | .agent.advisor.model = \"$new_model\"" "$GLOBAL_CONFIG_FILE" > "$temp_file" && mv "$temp_file" "$GLOBAL_CONFIG_FILE"
                    elif [ "$agent_key" = "medium" ]; then
                       $JQ ".agent.researcher.model = \"$new_model\" | .agent.tester.model = \"$new_model\"" "$GLOBAL_CONFIG_FILE" > "$temp_file" && mv "$temp_file" "$GLOBAL_CONFIG_FILE"
                    elif [ "$agent_key" = "fast" ]; then
                       $JQ ".agent.scout.model = \"$new_model\" | .agent.verifier.model = \"$new_model\"" "$GLOBAL_CONFIG_FILE" > "$temp_file" && mv "$temp_file" "$GLOBAL_CONFIG_FILE"
                    fi
                    
                  else
                     echo "Error: Global config not found. Please reboot to initialize."
                  fi
                }

                init_project() {
                  local choice
                  choice=$($GUM choose ${
                    lib.concatStringsSep " " (map (n: ''"${n}"'') (lib.attrNames mcpTemplates))
                  } --header "📦 Select Project Template (initializes in $PWD)" --cursor="▶ " --selected.foreground="212" --cursor.foreground="212")

                  if [ -z "$choice" ]; then echo "Operation cancelled."; return 1; fi

                  if [ -f "$LOCAL_JSONC_FILE" ] || [ -f "$PWD/.opencode/config.json" ]; then
                    if ! $GUM confirm "This will overwrite your existing opencode.jsonc. Continue?"; then
                      echo "Operation cancelled."; return 1
                    fi
                  fi

                  local template_name=$(echo "$choice" | tr ' /' '__')
                  local template_file="$TEMPLATES_DIR/$template_name.json"
                  
                  if [ ! -f "$template_file" ]; then echo "Error: Template not found."; return 1; fi

                  $JQ '.' "$template_file" > "$LOCAL_JSONC_FILE"
                  $GUM style --foreground 212 --border double --align center --padding "1 2" "✨ Project Initialized ✨" "Template: $choice" "Saved to: opencode.jsonc"
                }

                tui_menu() {
                  local context_msg="Context: Global"
                  if [ -f "$LOCAL_JSONC_FILE" ]; then context_msg="Context: Local Project ($LOCAL_JSONC_FILE)"; fi
                  
                  local cur_adv=$(get_current "advanced")
                  local cur_med=$(get_current "medium")
                  local cur_fast=$(get_current "fast")

                  # Build array of choices
                  local action
                  action=$($GUM choose \
                    "Init Project MCPs (Current Dir)" \
                    "Change Advanced Model (Builder, Planner, Advisor)" \
                    "Change Medium Model (Researcher, Tester)" \
                    "Change Fast Model (Scout, Verifier)" \
                    "Exit" \
                    --header "🤖 OpenCode Configuration Manager
        $context_msg
        Current Adv : $cur_adv
        Current Med : $cur_med
        Current Fast: $cur_fast" --cursor="▶ " --selected.foreground="212" --cursor.foreground="212")
                    
                  case "$action" in
                    "Init Project MCPs (Current Dir)") init_project ;;
                    "Change Advanced Model (Builder, Planner, Advisor)")
                      local adv_choice=$($GUM choose ${
                        lib.concatStringsSep " " (
                          map (n: ''"${n}"'') [
                            "gemini-3.1-pro-high"
                            "claude-opus"
                            "gemini-3-flash"
                            "kimi-2.5"
                            "minimax-2.5"
                          ]
                        )
                      } "Cancel" --header "Select Advanced Model")
                      if [ "$adv_choice" != "Cancel" ]; then
                        local selected_id
                        case "$adv_choice" in
                          ${lib.concatStringsSep "\n                  " (
                            lib.mapAttrsToList (name: id: ''"${name}") selected_id="${id}" ;;'') models
                          )}
                        esac
                        update_model_in_config "advanced" "$selected_id"
                        $GUM style --foreground 212 "✅ Switched Advanced to $adv_choice"
                      fi
                      ;;
                    "Change Medium Model (Researcher, Tester)")
                      local med_choice=$($GUM choose ${
                        lib.concatStringsSep " " (
                          map (n: ''"${n}"'') [
                            "gemini-3-flash"
                            "gemini-3.1-flash-image"
                            "gemini-3.1-pro-high"
                            "kimi-2.5"
                            "minimax-2.5"
                          ]
                        )
                      } "Cancel" --header "Select Medium Model")
                      if [ "$med_choice" != "Cancel" ]; then
                        local selected_id
                        case "$med_choice" in
                          ${lib.concatStringsSep "\n                  " (
                            lib.mapAttrsToList (name: id: ''"${name}") selected_id="${id}" ;;'') models
                          )}
                        esac
                        update_model_in_config "medium" "$selected_id"
                        $GUM style --foreground 212 "✅ Switched Medium to $med_choice"
                      fi
                      ;;
                    "Change Fast Model (Scout, Verifier)")
                      local fast_choice=$($GUM choose ${
                        lib.concatStringsSep " " (
                          map (n: ''"${n}"'') [
                            "kimi-2.5"
                            "gemini-3-flash"
                            "gemini-3.1-flash-image"
                            "gemini-3.1-pro-high"
                            "minimax-2.5"
                          ]
                        )
                      } "Cancel" --header "Select Fast Model")
                      if [ "$fast_choice" != "Cancel" ]; then
                        local selected_id
                        case "$fast_choice" in
                          ${lib.concatStringsSep "\n                  " (
                            lib.mapAttrsToList (name: id: ''"${name}") selected_id="${id}" ;;'') models
                          )}
                        esac
                        update_model_in_config "fast" "$selected_id"
                        $GUM style --foreground 212 "✅ Switched Fast to $fast_choice"
                      fi
                      ;;
                    *) exit 0 ;;
                  esac
                }

                if [ $# -eq 0 ]; then tui_menu; exit 0; fi

                case "''${1:-}" in
                  init) init_project ;;
                  *) echo "Usage: opencode-models [init]"; exit 1 ;;
                esac
      '';

      opencodeEnv = pkgs.buildEnv {
        name = "opencode-env";
        paths = languages.packages ++ [ pkgs.libreoffice ];
      };

      # Init script creates required cache/plugin directories before launching opencode
      # This ensures local plugins have correct symlinks required by OpenCode architecture
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

      opencodeWrapped = pkgs.runCommand "opencode-wrapped" { buildInputs = [ pkgs.makeWrapper ]; } ''
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
    in
    {
      environment.systemPackages = [
        opencodeWrapped
        opencodeModelSwitch
      ]
      ++ languages.packages;

      # Setup script to ensure files exist before mount
      system.activationScripts.opencode-persistence = {
        text = toolsPersistence.activationScript + opencodePersistence.activationScript;
        deps = [ "users" ];
      };

      # Bind mount for reliable persistence (apps can't overwrite)
      fileSystems = toolsPersistence.fileSystems // opencodePersistence.fileSystems;

      hjem.users.${user}.files = {
        # Deploy initial config structure
        "${configFile}".text = builtins.toJSON initialConfig;

        # Source skills & commands using hjem as requested
        ".config/opencode/skill".source = ./skill;
        ".config/opencode/command".source = ./command;
        ".config/opencode/plugin".source = ./plugin;
        ".config/opencode/AGENTS.md".source = ./AGENTS.md;
        ".config/opencode/prompts".source = ./prompts;
      };
    };
}
