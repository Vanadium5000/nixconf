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

      # Path to the persistent model selections
      stateFile = ./state.json;
      state =
        let
          exists = builtins.pathExists stateFile;
          content = if exists then builtins.readFile stateFile else "";
          isValid = exists && content != "" && content != " " && content != "{}";
          data = if isValid then builtins.fromJSON content else { };
        in
        {
          advanced = data.advanced or "cliproxyapi/gemini-3.1-pro-high";
          medium = data.medium or "cliproxyapi/gemini-3-flash";
          fast = data.fast or "cliproxyapi/gemini-3-flash";
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
              # Try to use a flash model for image generation if possible
              export IMAGE_MODEL="${state.medium}"
              exec ${pkgs.bun}/bin/bun ${../../../nixos/scripts/bunjs/mcp/image-gen.ts}
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
              exec ${pkgs.bun}/bin/bun ${../../../nixos/scripts/bunjs/mcp/slide-preview.ts}
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
          "cliproxyapi"
        ];
        mcp = mcpConfig;
        inherit (languages) formatter lsp;
        provider = providers.config;
      };

      # Generate initial fallback config so opencode has *something* to launch with if modified
      initialConfig = baseConfig // {
        agent = agentsConfig.mkAgentConfig {
          advancedModel = state.advanced;
          mediumModel = state.medium;
          fastModel = state.fast;
        };
      };

      # Define project MCP templates with rich comments for JSONC output
      mcpTemplates =
        let
          # Get all MCP names
          allMcpNames = lib.attrNames mcpConfig;

          mkTemplateJsonC =
            templateName: enabledMcpNames:
            let
              globallyEnabledNotInTemplate = lib.filterAttrs (
                name: cfg: (cfg.enabled or false) && !(builtins.elem name enabledMcpNames)
              ) mcpConfig;

              availableNotInTemplate = lib.filterAttrs (
                name: cfg: !(builtins.elem name enabledMcpNames) && !(cfg.enabled or false)
              ) mcpConfig;

              globalNames = lib.attrNames globallyEnabledNotInTemplate;
              availableNames = lib.attrNames availableNotInTemplate;
              allDataNames = globalNames ++ availableNames ++ enabledMcpNames;
              lastIdx = lib.length allDataNames - 1;

              mkLine =
                i: text:
                let
                  comma = if i == lastIdx then "" else ",";
                in
                "    ${text}${comma}";

              globalSection =
                if globalNames == [ ] then
                  [ ]
                else
                  [ "    // Globally enabled by default - disable if not needed" ]
                  ++ (lib.imap0 (i: name: mkLine i "// \"${name}\": { \"enabled\": false }") globalNames);

              availableSection =
                if availableNames == [ ] then
                  [ ]
                else
                  [ "    // Available: uncomment to enable" ]
                  ++ (lib.imap0 (
                    i: name: mkLine (i + lib.length globalNames) "// \"${name}\": { \"enabled\": true }"
                  ) availableNames);

              enabledSection = lib.imap0 (
                i: name:
                mkLine (i + lib.length globalNames + lib.length availableNames) "\"${name}\": { \"enabled\": true }"
              ) enabledMcpNames;

              result =
                globalSection
                ++ lib.optional (globalSection != [ ] && (availableSection != [ ] || enabledSection != [ ])) ""
                ++ availableSection
                ++ lib.optional (availableSection != [ ] && enabledSection != [ ]) ""
                ++ enabledSection;
            in
            "{\n  \"mcp\": {\n${lib.concatStringsSep "\n" result}\n  }\n}";
        in
        {
          "Web Development" = mkTemplateJsonC "Web Development" [
            "daisyui"
            "playwrite"
          ];
          "NixOS Config" = mkTemplateJsonC "NixOS Config" [
            "quickshell"
            "qmllint"
          ];
          "PowerPoint/Office Work" = mkTemplateJsonC "PowerPoint/Office Work" [
            "powerpoint"
            "slide_preview"
          ];
          "All MCPs" = mkTemplateJsonC "All MCPs" allMcpNames;
          "No MCPs" = mkTemplateJsonC "No MCPs" [ ];
          "Custom MCP File" = mkTemplateJsonC "Custom MCP File" [ ];
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
              ${value}
              EOF
            ''
          ) mcpTemplates
        )}
      '';

      # TUI for model/profile and template switching
      opencodeModelSwitch = pkgs.writeShellScriptBin "opencode-models" ''
        REPO_DIR="/home/matrix/nixconf/modules/nixos/terminal/opencode"
        MODELS_FILE="$REPO_DIR/models.json"
        STATE_FILE="$REPO_DIR/state.json"
        GLOBAL_CONFIG_FILE="$HOME/.config/opencode/config.json"
        LOCAL_JSONC_FILE="$PWD/opencode.jsonc"
        TEMPLATES_DIR="${configVariantsDir}/templates"
        JQ="${pkgs.jq}/bin/jq"
        GUM="${pkgs.gum}/bin/gum"
        SYSTEMCTL="${pkgs.systemd}/bin/systemctl"
        CURL="${pkgs.curl}/bin/curl"

        # Fetch models from CliProxyApi and update models.json
        sync_models() {
          local api_key="${self.secrets.CLIPROXYAPI_KEY}"
          local url="http://localhost:8317/v1beta/models"
          
          echo "Fetching models from $url..."
          local response
          response=$($CURL -s -H "Authorization: Bearer $api_key" "$url")
          
          if [ -z "$response" ] || [ "$(echo "$response" | $JQ '.models')" = "null" ]; then
            $GUM style --foreground 196 "Error: Failed to fetch models from API. Is the proxy running?"
            return 1
          fi

          # Transform CliProxyApi response to our models.json format
          # Group all models under a single unified provider
          local temp_json
          temp_json=$(mktemp)
          echo "$response" | $JQ '
            # Helper: get short ID (everything after the first /)
            def get_id: .name | split("/") | if length > 1 then .[1:] | join("/") else .[0] end;
            
            # Map a model object to our internal format
            def to_opencode(ctx; out): {
              key: get_id,
              value: {
                name: .displayName,
                context: (.inputTokenLimit // ctx),
                output: (.outputTokenLimit // out),
                modalities: {
                  input: ((.supportedInputModalities // []) | map(ascii_downcase) // ["text"]),
                  output: ((.supportedOutputModalities // []) | map(ascii_downcase) // ["text"])
                }
              }
            };

            # Filter and transform models into a single provider
            {
              providers: {
                "cliproxyapi": {
                  npm: "@ai-sdk/anthropic",
                  name: "CliProxyApi",
                  baseUrl: "http://127.0.0.1:8317/v1",
                  models: ([.models[] | to_opencode(128000; 32000)] | from_entries)
                }
              }
            }' > "$temp_json"
          
          if [ -s "$temp_json" ]; then
            mv "$temp_json" "$MODELS_FILE"
            $GUM style --foreground 212 "✅ Successfully synced models to $MODELS_FILE"
            $GUM style --foreground 212 "💡 Remember to git add the changes!"

            if $SYSTEMCTL is-active --quiet opencode-server 2>/dev/null; then
              $SYSTEMCTL restart opencode-server 2>/dev/null && $GUM style --foreground 99 "↻ Restarted opencode-server"
            fi
          else
            $GUM style --foreground 196 "Error: Failed to process models. API response may be malformed."
            rm -f "$temp_json"
            return 1
          fi
        }

        # Update both persistent state.json and runtime config.json
        update_state() {
          local tier="$1"
          local full_id="$2"
          
          # Update state.json (for rebuilds)
          if [ ! -f "$STATE_FILE" ] || [ ! -s "$STATE_FILE" ]; then echo "{}" > "$STATE_FILE"; fi
          local temp_state
          temp_state=$(mktemp)
          $JQ ".\"$tier\" = \"$full_id\"" "$STATE_FILE" > "$temp_state" && mv "$temp_state" "$STATE_FILE"
          
          # Update config.json (immediate)
          if [ -f "$GLOBAL_CONFIG_FILE" ]; then
            local temp_config
            temp_config=$(mktemp)
            
            # Ensure agent structure exists in config.json
            if ! $JQ 'has("agent")' "$GLOBAL_CONFIG_FILE" | grep -q "true"; then
              local bootstrap_config
              bootstrap_config=$(mktemp)
              $JQ ".agent = {}" "$GLOBAL_CONFIG_FILE" > "$bootstrap_config" && mv "$bootstrap_config" "$GLOBAL_CONFIG_FILE"
            fi

            case "$tier" in
              advanced)
                $JQ ".agent.build.model = \"$full_id\"
                   | .agent.plan.model = \"$full_id\"
                   | .agent[\"plan-reviewer\"].model = \"$full_id\"
                   | .agent.advisor.model = \"$full_id\"
                   | .agent.general.model = \"$full_id\"" \
                  "$GLOBAL_CONFIG_FILE" > "$temp_config" ;;
              medium)
                $JQ ".agent.researcher.model = \"$full_id\"
                   | .agent.tester.model = \"$full_id\"
                   | .agent.explore.model = \"$full_id\"" \
                  "$GLOBAL_CONFIG_FILE" > "$temp_config" ;;
              fast)
                $JQ ".agent.scout.model = \"$full_id\"
                   | .agent.verifier.model = \"$full_id\"" \
                  "$GLOBAL_CONFIG_FILE" > "$temp_config" ;;
            esac
            
            if [ -s "$temp_config" ]; then
              mv "$temp_config" "$GLOBAL_CONFIG_FILE"
              chmod 0600 "$GLOBAL_CONFIG_FILE"
            fi
          fi
        }

        # Searchable model picker using gum filter
        choose_model() {
          local tier="$1"
          local header="$2"
          
          # Generate list of "Provider: Model (ID)"
          local choices
          choices=$($JQ -r '.providers | to_entries | .[] | .key as $p | .value.models | to_entries | .[] | "\($p): \(.value.name) (\(.key))"' "$MODELS_FILE")
          
          local selection
          selection=$(echo "$choices" | $GUM filter --placeholder "Search models..." --header "$header")
          
          if [ -z "$selection" ]; then return 1; fi
          
          # Extract the provider/id from the selection (e.g., "antigravity-gemini: Gemini 3 Flash (gemini-3-flash)")
          local p_id
          p_id=$(echo "$selection" | sed -E 's/^([^:]+):.* \((.*)\)$/\1\/\2/')
          
          update_state "$tier" "$p_id"
          $GUM style --foreground 212 "✅ Set $tier tier to $p_id"
          
          if $SYSTEMCTL is-active --quiet opencode-server 2>/dev/null; then
            $SYSTEMCTL restart opencode-server 2>/dev/null && $GUM style --foreground 99 "↻ Restarted opencode-server"
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

          local template_name
          template_name=$(echo "$choice" | tr ' /' '__')
          local template_file="$TEMPLATES_DIR/$template_name.json"

          if [ ! -f "$template_file" ]; then echo "Error: Template not found."; return 1; fi

          cat "$template_file" > "$LOCAL_JSONC_FILE"
          $GUM style --foreground 212 --border double --align center --padding "1 2" "✨ Project Initialized ✨" "Template: $choice" "Saved to: opencode.jsonc"
        }

        tui_menu() {
          local context_msg="Context: Global"
          if [ -f "$LOCAL_JSONC_FILE" ]; then context_msg="Context: Local Project ($LOCAL_JSONC_FILE)"; fi

          local cur_adv cur_med cur_fast
          if [ -f "$STATE_FILE" ] && [ -s "$STATE_FILE" ]; then
            cur_adv=$($JQ -r '.advanced // "N/A"' "$STATE_FILE" 2>/dev/null || echo "N/A")
            cur_med=$($JQ -r '.medium // "N/A"' "$STATE_FILE" 2>/dev/null || echo "N/A")
            cur_fast=$($JQ -r '.fast // "N/A"' "$STATE_FILE" 2>/dev/null || echo "N/A")
          else
            cur_adv="[Default]"
            cur_med="[Default]"
            cur_fast="[Default]"
          fi

          local sync_warning=""
          if [ ! -f "$MODELS_FILE" ] || [ ! -s "$MODELS_FILE" ]; then
            sync_warning=" (⚠️ Models list empty, please sync!)"
          fi

          local action
          action=$($GUM choose \
            "Sync Models from API$sync_warning" \
            "Change Advanced Model (Builder, Planner, Advisor, General)" \
            "Change Medium Model (Researcher, Tester, Explore)" \
            "Change Fast Model (Scout, Verifier)" \
            "Init Project MCPs (Current Dir)" \
            "Exit" \
            --header "🤖 OpenCode Configuration Manager
        $context_msg
        Current Adv : $cur_adv
        Current Med : $cur_med
        Current Fast: $cur_fast" --cursor="▶ " --selected.foreground="212" --cursor.foreground="212")

          case "$action" in
            "Sync Models from API"*) sync_models ;;
            "Change Advanced Model (Builder, Planner, Advisor, General)") choose_model "advanced" "Select Advanced Model" ;;
            "Change Medium Model (Researcher, Tester, Explore)") choose_model "medium" "Select Medium Model" ;;
            "Change Fast Model (Scout, Verifier)") choose_model "fast" "Select Fast Model" ;;
            "Init Project MCPs (Current Dir)") init_project ;;
            *) exit 0 ;;
          esac
        }

        if [ $# -eq 0 ]; then tui_menu; exit 0; fi

        case "''${1:-}" in
          sync) sync_models ;;
          init) init_project ;;
          *) echo "Usage: opencode-models [sync|init]"; exit 1 ;;
        esac
      '';

      opencodeEnv = pkgs.buildEnv {
        name = "opencode-env";
        paths = languages.packages ++ [
          pkgs.libreoffice
          pkgs.python3
          pkgs.stdenv.cc
          pkgs.gnumake
        ];
      };

      # Init script creates required cache/plugin directories before launching opencode
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

      # Persistence configuration
      toolsPersistence = self.lib.persistence.mkPersistent {
        method = "bind";
        inherit user;
        fileName = "antigravity_tools";
        targetFile = "/home/${user}/.antigravity_tools";
        isDirectory = true;
      };

      opencodePersistence = self.lib.persistence.mkPersistent {
        method = "bind";
        inherit user;
        fileName = "opencode";
        targetFile = "/home/${user}/.local/share/opencode";
        isDirectory = true;
      };

      opencodeMemPersistence = self.lib.persistence.mkPersistent {
        method = "bind";
        inherit user;
        fileName = "opencode-mem";
        targetFile = "/home/${user}/.opencode-mem";
        isDirectory = true;
      };

      opencodeMemConfig = {
        storagePath = "/home/${user}/.opencode-mem/data";
        embeddingModel = "Xenova/nomic-embed-text-v1";
        memoryProvider = "openai-chat";
        memoryModel = state.fast;
        memoryApiUrl = "http://127.0.0.1:8317/v1";
        memoryApiKey = self.secrets.CLIPROXYAPI_KEY;
        autoCaptureEnabled = true;
        webServerEnabled = true;
        webServerPort = 4747;
        chatMessage = {
          enabled = true;
          maxMemories = 3;
          injectOn = "first";
        };
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
          + opencodeMemPersistence.activationScript;
        deps = [ "users" ];
      };

      fileSystems =
        toolsPersistence.fileSystems
        // opencodePersistence.fileSystems
        // opencodeMemPersistence.fileSystems;

      hjem.users.${user}.files = {
        "${configFile}" = {
          text = builtins.toJSON initialConfig;
          type = "copy";
          permissions = "0600";
        };

        ".config/opencode/skill" = {
          source = ./skill;
          type = "copy";
          permissions = "0755";
        };
        ".config/opencode/command" = {
          source = ./command;
          type = "copy";
          permissions = "0755";
        };
        ".config/opencode/plugin" = {
          source = ./plugin;
          type = "copy";
          permissions = "0755";
        };
        ".config/opencode/AGENTS.md" = {
          source = ./_AGENTS.md;
          type = "copy";
          permissions = "0644";
        };
        ".config/opencode/package.json" = {
          source = ./_package.json;
          type = "copy";
          permissions = "0644";
        };
        ".config/opencode/prompts" = {
          source = ./prompts;
          type = "copy";
          permissions = "0755";
        };
        ".config/opencode/opencode-mem.jsonc" = {
          text = builtins.toJSON opencodeMemConfig;
          type = "copy";
          permissions = "0644";
        };
      };
    };
}
