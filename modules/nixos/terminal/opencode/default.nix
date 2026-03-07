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

      # Define project MCP templates with rich comments for JSONC output
      # Each template includes:
      # - Enabled MCPs (uncommented, enabled: true)
      # - Available MCPs not in template (commented, enabled: true) - uncomment to add
      # - Globally enabled MCPs (commented, enabled: false) - disable if not needed
      mcpTemplates =
        let
          # Get all MCP names
          allMcpNames = lib.attrNames mcpConfig;

          # Generate JSONC with comments for a template
          # This produces a string with comments showing:
          # 1. Globally enabled MCPs not in template (commented, enabled: false)
          # 2. Available MCPs not in template (commented, enabled: true)
          # 3. Enabled MCPs in template (uncommented, enabled: true)
          mkTemplateJsonC =
            templateName: enabledMcpNames:
            let
              # MCPs globally enabled but NOT in this template (show as disabled)
              globallyEnabledNotInTemplate = lib.filterAttrs (
                name: cfg: (cfg.enabled or false) && !(builtins.elem name enabledMcpNames)
              ) mcpConfig;

              # MCPs disabled in this template (not in enabledMcpNames list)
              # Exclude those that are globally enabled since they're handled above
              availableNotInTemplate = lib.filterAttrs (
                name: cfg: !(builtins.elem name enabledMcpNames) && !(cfg.enabled or false)
              ) mcpConfig;

              globalNames = lib.attrNames globallyEnabledNotInTemplate;
              availableNames = lib.attrNames availableNotInTemplate;

              # All actual data items in order: global, then available, then enabled
              # This helps us determine where to put the final trailing comma (or omit it)
              allDataNames = globalNames ++ availableNames ++ enabledMcpNames;
              lastIdx = lib.length allDataNames - 1;

              # Helper to generate a line with a comma if it's not the absolute last item
              mkLine =
                i: text:
                let
                  comma = if i == lastIdx then "" else ",";
                in
                "    ${text}${comma}";

              # Section construction
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

              # Combine sections with blank lines
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
          # Use JSONC for interactive templates
          # Globally enabled MCPs (websearch, context7, gh_grep, markdown_lint, image_gen)
          # are omitted from the enabled list so they appear in the "Globally enabled" section.
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

      # Model display names in selection order — shared across all tiers
      modelNames = lib.attrNames models;

      # Gum choose arguments for the model picker (same order for all tiers)
      gumModelChoices = lib.concatStringsSep " " (map (n: ''"${n}"'') modelNames);

      # Single case block mapping display names → provider model IDs
      modelCaseBlock = lib.concatStringsSep "\n          " (
        lib.mapAttrsToList (name: id: ''"${name}") selected_id="${id}" ;;'') models
      );

      # TUI for model/profile and template switching
      opencodeModelSwitch = pkgs.writeShellScriptBin "opencode-models" ''
        GLOBAL_CONFIG_FILE="$HOME/.config/opencode/config.json"
        LOCAL_JSONC_FILE="$PWD/opencode.jsonc"
        TEMPLATES_DIR="${configVariantsDir}/templates"
        JQ="${pkgs.jq}/bin/jq"
        GUM="${pkgs.gum}/bin/gum"
        SYSTEMCTL="${pkgs.systemd}/bin/systemctl"

        # Resolve a display name to its provider model ID
        resolve_model_id() {
          local name="$1"
          local selected_id=""
          case "$name" in
            ${modelCaseBlock}
          esac
          echo "$selected_id"
        }

        # Read the current model for a tier from the config
        # Each tier uses a representative agent (build/researcher/scout)
        get_current() {
          local tier="$1"
          if [ ! -f "$GLOBAL_CONFIG_FILE" ]; then echo "unknown"; return; fi
          case "$tier" in
            advanced)  $JQ -r '.agent.build.model // empty' "$GLOBAL_CONFIG_FILE" 2>/dev/null ;;
            medium)    $JQ -r '.agent.researcher.model // empty' "$GLOBAL_CONFIG_FILE" 2>/dev/null ;;
            fast)      $JQ -r '.agent.scout.model // empty' "$GLOBAL_CONFIG_FILE" 2>/dev/null ;;
          esac
        }

        # Update all agents in a tier to use the given model
        update_model_in_config() {
          local tier="$1"
          local new_model="$2"
          if [ ! -f "$GLOBAL_CONFIG_FILE" ]; then
            echo "Error: Global config not found. Please reboot to initialize."
            return 1
          fi
          local temp_file
          temp_file=$(mktemp)
          case "$tier" in
            advanced)
              $JQ ".agent.build.model = \"$new_model\"
                 | .agent.plan.model = \"$new_model\"
                 | .agent[\"plan-reviewer\"].model = \"$new_model\"
                 | .agent.advisor.model = \"$new_model\"" \
                "$GLOBAL_CONFIG_FILE" > "$temp_file" && mv "$temp_file" "$GLOBAL_CONFIG_FILE" ;;
            medium)
              $JQ ".agent.researcher.model = \"$new_model\"
                 | .agent.tester.model = \"$new_model\"" \
                "$GLOBAL_CONFIG_FILE" > "$temp_file" && mv "$temp_file" "$GLOBAL_CONFIG_FILE" ;;
            fast)
              $JQ ".agent.scout.model = \"$new_model\"
                 | .agent.verifier.model = \"$new_model\"" \
                "$GLOBAL_CONFIG_FILE" > "$temp_file" && mv "$temp_file" "$GLOBAL_CONFIG_FILE" ;;
          esac
        }

        # Restart opencode-server if it's running so config changes take effect
        maybe_restart_server() {
          if $SYSTEMCTL is-active --quiet opencode-server 2>/dev/null; then
            $SYSTEMCTL restart opencode-server 2>/dev/null && \
              $GUM style --foreground 99 "↻ Restarted opencode-server" || \
              $GUM style --foreground 196 "⚠ Failed to restart opencode-server"
          fi
        }

        # Prompt the user to pick a model for a tier and apply it
        choose_model() {
          local tier="$1"
          local header="$2"
          local choice
          choice=$($GUM choose ${gumModelChoices} "Cancel" \
            --header "$header" --cursor="▶ " --selected.foreground="212" --cursor.foreground="212")

          if [ -z "$choice" ] || [ "$choice" = "Cancel" ]; then return 1; fi
          local selected_id
          selected_id=$(resolve_model_id "$choice")
          update_model_in_config "$tier" "$selected_id"
          $GUM style --foreground 212 "✅ Switched $tier to $choice"
          maybe_restart_server
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

          # Copy template directly (JSONC with comments, not valid JSON)
          cat "$template_file" > "$LOCAL_JSONC_FILE"
          $GUM style --foreground 212 --border double --align center --padding "1 2" "✨ Project Initialized ✨" "Template: $choice" "Saved to: opencode.jsonc"
        }

        tui_menu() {
          local context_msg="Context: Global"
          if [ -f "$LOCAL_JSONC_FILE" ]; then context_msg="Context: Local Project ($LOCAL_JSONC_FILE)"; fi

          local cur_adv cur_med cur_fast
          cur_adv=$(get_current "advanced")
          cur_med=$(get_current "medium")
          cur_fast=$(get_current "fast")

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
              choose_model "advanced" "Select Advanced Model" ;;
            "Change Medium Model (Researcher, Tester)")
              choose_model "medium" "Select Medium Model" ;;
            "Change Fast Model (Scout, Verifier)")
              choose_model "fast" "Select Fast Model" ;;
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
        ".config/opencode/AGENTS.md".source = ./_AGENTS.md;
        ".config/opencode/package.json".source = ./_package.json;
        ".config/opencode/prompts".source = ./prompts;
      };
    };
}
