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
      # These path helpers are reused across generated configs, persistence, and
      # the TUI wrapper, so keep them close to the top-level module inputs.
      user = config.preferences.user.username;
      homeDirectory = config.preferences.paths.homeDirectory;
      configDirectory = config.preferences.paths.configDirectory;
      publicBaseDomain = self.secrets.PUBLIC_BASE_DOMAIN;

      # Existing adjacent helpers already split stable data domains cleanly.
      # Keep those imports, but keep the runtime assembly in this file so future
      # contract-sensitive changes stay visible in one place.
      languages = import ./_languages.nix { inherit pkgs self; };
      providers = import ./_providers.nix {
        inherit self lib;
      };
      pluginsConfig = import ./_plugins.nix;
      categoriesConfig = import ./_categories.nix { inherit lib; };
      opencode = pkgs.unstable.opencode;

      # state.json is repo-owned so model/category choices survive wrapper runs
      # and can be reviewed/committed like any other configuration change.
      stateFile = ./state.json;
      state = categoriesConfig.mkState { inherit stateFile; };

      # MCP server configuration is shared by the global OpenCode config and the
      # project template generator, so keep one source of truth here.
      mcpConfig = {
        gh_grep = {
          # grep.app is the default public code-search MCP used across this repo.
          type = "remote";
          url = "https://mcp.grep.app/";
          enabled = true;
          timeout = 20000;
        };

        context7 = {
          # Context7 keeps API docs current without bundling snapshots locally.
          type = "remote";
          url = "https://mcp.context7.com/mcp";
          enabled = true;
          timeout = 20000;
        };

        markdown_lint = {
          # Enabled globally so repo guidance and generated plans stay lintable.
          type = "local";
          command = [
            "${inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.markdown-lint-mcp}/bin/markdown-lint-mcp"
          ];
          enabled = true;
          timeout = 10000;
        };

        # Remote tool: High-quality parallel web search with deep research capabilities.
        # Already declared by Oh-My-OpenAgent.
        # websearch = {
        #   type = "remote";
        #   url = "https://mcp.exa.ai/mcp?exaApiKey=${self.secrets.EXA_API_KEY}&tools=web_search_exa,deep_search_exa,get_code_context_exa,crawling_exa,deep_researcher_start,deep_researcher_check";
        #   enabled = true;
        #   timeout = 30000;
        # };

        image_gen = {
          # Resolve the first image-capable model at runtime so model sync stays
          # authoritative and repo-owned modality overrides apply immediately
          # without requiring a rebuild.
          type = "local";
          command = [
            (pkgs.writeShellScript "image-gen-mcp-wrapper" ''
              export CLIPROXYAPI_KEY="${self.secrets.CLIPROXYAPI_KEY}"
              export CLIPROXYAPI_BASE_URL="https://cliproxyapi.${publicBaseDomain}/v1"
              MODELS_FILE="${configDirectory}/modules/nixos/terminal/opencode/models.json"
              OVERRIDES_FILE="${configDirectory}/modules/nixos/terminal/opencode/_model-capability-overrides.json"

              # Prefer the first runtime-effective model that advertises image output.
              # Source of truth is the repo models cache plus repo-owned JSON overrides.
              if [ -f "$OVERRIDES_FILE" ] && [ -s "$OVERRIDES_FILE" ]; then
                IMAGE_MODEL="$(${pkgs.jq}/bin/jq -r --slurpfile overrides "$OVERRIDES_FILE" '
                  first(
                    ((.providers.cliproxyapi.models // {}) * ($overrides[0] // {}))
                    | to_entries[]
                    | select(((.value.modalities.output // []) | index("image")) != null)
                    | "cliproxyapi/\(.key)"
                  ) // empty
                ' "$MODELS_FILE")"
              else
                IMAGE_MODEL="$(${pkgs.jq}/bin/jq -r '
                  first(
                    (.providers.cliproxyapi.models // {})
                    | to_entries[]
                    | select(((.value.modalities.output // []) | index("image")) != null)
                    | "cliproxyapi/\(.key)"
                  ) // empty
                ' "$MODELS_FILE")"
              fi

              exec ${pkgs.bun}/bin/bun ${../../../nixos/scripts/bunjs/mcp/image-gen.ts}
            '')
          ];
          enabled = true;
          timeout = 60000;
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
      initialConfig = baseConfig;

      ohMyOpencodeConfig = categoriesConfig.mkOhMyConfig { inherit state; };

      opencodeModelsMetadata = categoriesConfig.mkMenuMetadata // {
        menu = categoriesConfig.mkMenuMetadata.menu // {
          reasoningEffortHeader = "Select reasoning effort for this model";
        };
      };

      runtimeConfigDir = pkgs.runCommand "opencode-runtime-configs" { } ''
        mkdir -p $out
        cat > "$out/opencode-base.json" <<'EOF'
        ${builtins.toJSON initialConfig}
        EOF
        cat > "$out/oh-my-opencode-base.json" <<'EOF'
        ${builtins.toJSON ohMyOpencodeConfig}
        EOF
        cat > "$out/opencode-mem-base.json" <<'EOF'
        ${builtins.toJSON opencodeMemConfig}
        EOF
        cat > "$out/opencode-models-metadata.json" <<'EOF'
        ${builtins.toJSON opencodeModelsMetadata}
        EOF
      '';

      # Templates live in the store so the TUI can switch project bootstraps
      # without mutating repo files or recomputing JSONC snippets by hand.
      mcpTemplates =
        let
          allMcpNames = lib.attrNames mcpConfig;

          mkTemplateJsonC =
            _: enabledMcpNames:
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
          "All MCPs" = mkTemplateJsonC "All MCPs" allMcpNames;
          "No MCPs" = mkTemplateJsonC "No MCPs" [ ];
          "Custom MCP File" = mkTemplateJsonC "Custom MCP File" [ ];
        };

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

      # These seed files repopulate the repo-owned mutable state when the user
      # has not created local copies yet.
      stateAssetsDir = pkgs.runCommand "opencode-state-assets" { } ''
        mkdir -p "$out"
        cp ${./models.json} "$out/models.json"
        cp ${./state.json} "$out/state.json"
        cp ${./presets.json} "$out/presets.json"
        cp ${./_model-capability-overrides.json} "$out/_model-capability-overrides.json"
      '';

      # TUI for model/profile and template switching
      opencodeModelSwitch = pkgs.writeShellScriptBin "opencode-models" ''
        # shell
        REPO_DIR="${configDirectory}/modules/nixos/terminal/opencode"
        MODELS_FILE="$REPO_DIR/models.json"
        STATE_FILE="$REPO_DIR/state.json"
        PRESETS_FILE="$REPO_DIR/presets.json"
        OVERRIDES_FILE="$REPO_DIR/_model-capability-overrides.json"
        GLOBAL_CONFIG_FILE="$HOME/.config/opencode/config.json"
        GLOBAL_OMA_FILE="$HOME/.config/opencode/oh-my-opencode.jsonc"
        # Compatibility alias used by some OpenCode/Oh-My-* plugin paths.
        # Keep both files in sync so runtime cannot silently read stale models.
        GLOBAL_OPENAGENT_FILE="$HOME/.config/opencode/oh-my-openagent.jsonc"
        GLOBAL_MEM_FILE="$HOME/.config/opencode/opencode-mem.jsonc"
        LOCAL_JSONC_FILE="$PWD/opencode.jsonc"
        TEMPLATES_DIR="${configVariantsDir}/templates"
        BASE_CONFIG_FILE="${runtimeConfigDir}/opencode-base.json"
        BASE_OMA_FILE="${runtimeConfigDir}/oh-my-opencode-base.json"
        BASE_MEM_FILE="${runtimeConfigDir}/opencode-mem-base.json"
        METADATA_FILE="${runtimeConfigDir}/opencode-models-metadata.json"
        JQ="${pkgs.jq}/bin/jq"
        GUM="${pkgs.gum}/bin/gum"
        SYSTEMCTL="${pkgs.systemd}/bin/systemctl"
        CURL="${pkgs.curl}/bin/curl"

        ensure_repo_state_files() {
          mkdir -p "$REPO_DIR"

          if [ ! -f "$MODELS_FILE" ]; then
            cp "${stateAssetsDir}/models.json" "$MODELS_FILE"
          fi

          if [ ! -f "$STATE_FILE" ]; then
            cp "${stateAssetsDir}/state.json" "$STATE_FILE"
          fi

          if [ ! -f "$PRESETS_FILE" ]; then
            cp "${stateAssetsDir}/presets.json" "$PRESETS_FILE"
          fi

          if [ ! -f "$OVERRIDES_FILE" ]; then
            cp "${stateAssetsDir}/_model-capability-overrides.json" "$OVERRIDES_FILE"
          fi
        }

        get_effective_models_json() {
          ensure_repo_state_files

          if [ -f "$OVERRIDES_FILE" ] && [ -s "$OVERRIDES_FILE" ]; then
            $JQ -cS --slurpfile overrides "$OVERRIDES_FILE" '
              ((.providers.cliproxyapi.models // {}) * ($overrides[0] // {}))
            ' "$MODELS_FILE"
          else
            $JQ -cS '(.providers.cliproxyapi.models // {})' "$MODELS_FILE"
          fi
        }

        get_effective_model_field() {
          local provider="$1"
          local model_id="$2"
          local jq_expr="$3"

          ensure_repo_state_files

          if [ -f "$OVERRIDES_FILE" ] && [ -s "$OVERRIDES_FILE" ]; then
            $JQ -r --arg provider "$provider" --arg model_id "$model_id" --slurpfile overrides "$OVERRIDES_FILE" "
              (((.providers[\$provider].models // {}) * (\$overrides[0] // {}))[\$model_id] // {})
              | ''${jq_expr}
            " "$MODELS_FILE"
          else
            $JQ -r --arg provider "$provider" --arg model_id "$model_id" "
              (.providers[\$provider].models[\$model_id] // {})
              | ''${jq_expr}
            " "$MODELS_FILE"
          fi
        }

        ensure_state_file() {
          ensure_repo_state_files
          if [ ! -f "$STATE_FILE" ] || [ ! -s "$STATE_FILE" ]; then
            printf '{"categories":{}}\n' > "$STATE_FILE"
          fi
        }

        ensure_presets_file() {
          ensure_repo_state_files
          if [ ! -f "$PRESETS_FILE" ] || [ ! -s "$PRESETS_FILE" ]; then
            printf '{"presets":{}}\n' > "$PRESETS_FILE"
          fi
        }

        get_menu_text() {
          local key="$1"
          $JQ -r --arg key "$key" '.menu[$key]' "$METADATA_FILE"
        }

        get_group_model() {
          local group_id="$1"
          ensure_state_file
          local data
          data=$($JQ -r --arg category_id "$group_id" '.categories[$category_id] // empty' "$STATE_FILE")
          if [ -n "$data" ]; then
            # If it is a JSON object, extract the model field
            if echo "$data" | grep -q "^{"; then
              echo "$data" | $JQ -r '.model'
            else
              printf '%s\n' "$data"
            fi
          else
            $JQ -r --arg category_id "$group_id" '.categories[$category_id].defaultModel' "$METADATA_FILE"
          fi
        }

        get_group_reasoning_effort() {
          local group_id="$1"
          ensure_state_file
          local data
          data=$($JQ -r --arg category_id "$group_id" '.categories[$category_id] // empty' "$STATE_FILE")
          if [ -n "$data" ] && echo "$data" | grep -q "^{"; then
            echo "$data" | $JQ -r '.reasoningEffort // empty'
          fi
        }

        config_file_matches_state() {
          local cfg_file="$1"

          if [ ! -f "$cfg_file" ] || [ ! -s "$cfg_file" ]; then
            return 1
          fi

          local mismatch=0
          while IFS=$'\t' read -r category_id; do
            local state_model
            local state_effort
            local config_model
            local config_effort
            state_model=$(get_group_model "$category_id")
            state_effort=$(get_group_reasoning_effort "$category_id")

            config_model=$($JQ -r --arg category_id "$category_id" '
              .categories[$category_id]
              | if type == "object" then .model else . end
            ' "$cfg_file")
            config_effort=$($JQ -r --arg category_id "$category_id" '
              .categories[$category_id]
              | if type == "object" then (.reasoningEffort // "") else "" end
            ' "$cfg_file")

            if [ "$state_model" != "$config_model" ] || [ "$state_effort" != "$config_effort" ]; then
              mismatch=1
              break
            fi
          done < <($JQ -r '.categories | keys[]' "$METADATA_FILE")

          [ "$mismatch" -eq 0 ]
        }

        config_file_matches_effective_models() {
          local cfg_file="$1"

          if [ ! -f "$cfg_file" ] || [ ! -s "$cfg_file" ]; then
            return 1
          fi

          local effective_models
          local config_models
          effective_models=$(get_effective_models_json)
          config_models=$($JQ -cS '.provider.cliproxyapi.models // {}' "$cfg_file")

          [ "$effective_models" = "$config_models" ]
        }

        mem_config_matches_state() {
          local cfg_file="$1"

          if [ ! -f "$cfg_file" ] || [ ! -s "$cfg_file" ]; then
            return 1
          fi

          local state_model
          local config_model
          state_model=$(get_group_model "deep")
          config_model=$($JQ -r '.memoryModel // empty' "$cfg_file")

          [ "$state_model" = "$config_model" ]
        }

        config_out_of_date() {
          ensure_state_file
          if ! config_file_matches_effective_models "$GLOBAL_CONFIG_FILE"; then
            return 0
          fi

          if ! config_file_matches_state "$GLOBAL_OMA_FILE"; then
            return 0
          fi

          if ! config_file_matches_state "$GLOBAL_OPENAGENT_FILE"; then
            return 0
          fi

          if ! mem_config_matches_state "$GLOBAL_MEM_FILE"; then
            return 0
          fi

          return 1
        }

        sync_config_from_state() {
          local quiet="''${1:-0}"

          if config_out_of_date; then
            rebuild_runtime_configs
            if [ "$quiet" -ne 1 ]; then
              $GUM style --foreground 212 "✅ Synced OpenCode config from state"
            fi
          fi
        }

        rebuild_runtime_configs() {
          ensure_state_file

          local effective_models
          effective_models=$(get_effective_models_json)

          local opencode_tmp
          opencode_tmp=$(mktemp)
          $JQ --argjson models "$effective_models" '
            .provider.cliproxyapi.models = $models
          ' "$BASE_CONFIG_FILE" > "$opencode_tmp"

          mkdir -p "$(dirname "$GLOBAL_CONFIG_FILE")"
          mv "$opencode_tmp" "$GLOBAL_CONFIG_FILE"
          chmod 0600 "$GLOBAL_CONFIG_FILE"

          local oma_tmp
          oma_tmp=$(mktemp)
          cp "$BASE_OMA_FILE" "$oma_tmp"

          while IFS=$'\t' read -r category_id; do
            local model
            model=$(get_group_model "$category_id")
            local effort
            effort=$(get_group_reasoning_effort "$category_id")

            local next_tmp
            next_tmp=$(mktemp)
            if [ -n "$effort" ]; then
              $JQ --arg category_id "$category_id" --arg model "$model" --arg effort "$effort" \
                '.categories[$category_id].model = $model | .categories[$category_id].reasoningEffort = $effort' \
                "$oma_tmp" > "$next_tmp"
            else
              $JQ --arg category_id "$category_id" --arg model "$model" \
                '.categories[$category_id].model = $model' \
                "$oma_tmp" > "$next_tmp"
            fi
            mv "$next_tmp" "$oma_tmp"
          done < <($JQ -r '.categories | keys[]' "$METADATA_FILE")

          mkdir -p "$(dirname "$GLOBAL_OMA_FILE")"
          cp "$oma_tmp" "$GLOBAL_OMA_FILE"
          chmod 0600 "$GLOBAL_OMA_FILE"

          # Keep compatibility alias in lock-step with the canonical OMO file.
          cp "$oma_tmp" "$GLOBAL_OPENAGENT_FILE"
          chmod 0600 "$GLOBAL_OPENAGENT_FILE"

          rm -f "$oma_tmp"

          local mem_tmp
          mem_tmp=$(mktemp)
          $JQ --arg model "$(get_group_model "deep")" '.memoryModel = $model' "$BASE_MEM_FILE" > "$mem_tmp"

          mkdir -p "$(dirname "$GLOBAL_MEM_FILE")"
          mv "$mem_tmp" "$GLOBAL_MEM_FILE"
          chmod 0644 "$GLOBAL_MEM_FILE"

        }

        # Fetch models from CliProxyApi and update models.json
        sync_models() {
          local api_key="${self.secrets.CLIPROXYAPI_KEY}"
          local url="https://cliproxyapi.${publicBaseDomain}/v1beta/models"
          
          ensure_repo_state_files

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
            
            # Map a model object to our internal format.
            # Preserve incomplete upstream metadata by omitting empty or
            # missing optional fields rather than inventing defaults.
            def to_opencode:
              get_id as $id
              | (.supportedInputModalities // [] | map(ascii_downcase)) as $input_modalities
              | (.supportedOutputModalities // [] | map(ascii_downcase)) as $output_modalities
              # Models that require explicit reasoning_effort levels (no "auto" support)
              | (if $id == "kimi-k2.5" or ($id | test("kimi-k2.5")) then ["low", "medium", "high"] else null end) as $reasoning_efforts
              | {
                  key: $id,
                  value: (
                    {
                      name: .displayName
                    }
                    + (if .inputTokenLimit != null then { context: .inputTokenLimit } else {} end)
                    + (if .outputTokenLimit != null then { output: .outputTokenLimit } else {} end)
                    + (if $reasoning_efforts != null then { reasoning_effort: $reasoning_efforts } else {} end)
                    +
                      (if (($input_modalities | length) > 0) or (($output_modalities | length) > 0) then
                        {
                          modalities:
                            ((if ($input_modalities | length) > 0 then { input: $input_modalities } else {} end)
                            + (if ($output_modalities | length) > 0 then { output: $output_modalities } else {} end))
                        }
                      else
                        {}
                      end)
                  )
                };

            # Filter and transform models into a single provider
            {
              providers: {
                "cliproxyapi": {
                  npm: "@ai-sdk/anthropic",
                  name: "CliProxyApi",
                  baseUrl: "http://127.0.0.1:8317/v1",
                  models: ([.models[] | to_opencode] | sort_by(.key) | from_entries)
                }
              }
            }' > "$temp_json"
          
          if [ -s "$temp_json" ]; then
            mv "$temp_json" "$MODELS_FILE"
            $GUM style --foreground 212 "✅ Successfully synced models to $MODELS_FILE"
            $GUM style --foreground 212 "💡 Remember to git add the changes!"
            rebuild_runtime_configs
          else
            $GUM style --foreground 196 "Error: Failed to process models. API response may be malformed."
            rm -f "$temp_json"
            return 1
          fi
        }

        update_group_state() {
          local group_id="$1"
          local full_id="$2"
          local effort="$3"

          ensure_state_file
          local temp_state
          temp_state=$(mktemp)
          
          if [ -n "$effort" ]; then
            $JQ --arg category_id "$group_id" --arg full_id "$full_id" --arg effort "$effort" \
              '.categories[$category_id] = {model: $full_id, reasoningEffort: $effort}' "$STATE_FILE" > "$temp_state"
          else
            $JQ --arg category_id "$group_id" --arg full_id "$full_id" \
              '.categories[$category_id] = $full_id' "$STATE_FILE" > "$temp_state"
          fi
          
          mv "$temp_state" "$STATE_FILE"
          rebuild_runtime_configs
        }

        update_multiple_groups_state() {
          local full_id="$1"
          local effort="$2"
          shift 2

          if [ $# -eq 0 ]; then
            return 1
          fi

          ensure_state_file
          local ids_json
          ids_json=$(printf '%s\n' "$@" | $JQ -Rsc 'split("\n") | map(select(length > 0))')

          local temp_state
          temp_state=$(mktemp)
          
          if [ -n "$effort" ]; then
            $JQ --arg full_id "$full_id" --arg effort "$effort" --argjson category_ids "$ids_json" '
              .categories = (.categories // {})
              | reduce $category_ids[] as $category_id (.;
                  .categories[$category_id] = {model: $full_id, reasoningEffort: $effort}
                )
            ' "$STATE_FILE" > "$temp_state"
          else
            $JQ --arg full_id "$full_id" --argjson category_ids "$ids_json" '
              .categories = (.categories // {})
              | reduce $category_ids[] as $category_id (.;
                  .categories[$category_id] = $full_id
                )
            ' "$STATE_FILE" > "$temp_state"
          fi

          mv "$temp_state" "$STATE_FILE"
          rebuild_runtime_configs
        }

        get_model_name() {
          local full_id="$1"
          local provider="''${full_id%%/*}"
          local model_id="''${full_id#*/}"
          local name
          name=$(get_effective_model_field "$provider" "$model_id" '.name // empty')
          if [ -n "$name" ]; then
            printf '%s\n' "$name"
          else
            printf '%s\n' "$model_id"
          fi
        }

        model_picker_lines() {
          if [ -f "$OVERRIDES_FILE" ] && [ -s "$OVERRIDES_FILE" ]; then
            $JQ -r --slurpfile overrides "$OVERRIDES_FILE" '
              ((.providers.cliproxyapi.models // {}) * ($overrides[0] // {}))
              | to_entries
              | .[]
              | "cliproxyapi/\(.key)\tcliproxyapi: \(.value.name) (\(.key))"
            ' "$MODELS_FILE"
          else
            $JQ -r '
              .providers
              | to_entries
              | .[]
              | .key as $provider
              | .value.models
              | to_entries
              | .[]
              | "\($provider)/\(.key)\t\($provider): \(.value.name) (\(.key))"
            ' "$MODELS_FILE"
          fi
        }

        pick_model_id() {
          local header="$1"
          local selection
          selection=$(model_picker_lines | $GUM filter --placeholder "Search models..." --header "$header")

          if [ -z "$selection" ]; then
            return 1
          fi

          printf '%s\n' "$selection" | cut -f1
        }

        # Searchable model picker using gum filter
        choose_categories() {
          local selected
          selected=$($JQ -r '.categories | to_entries[] | "\(.key)\t\(.value.label) [\(.key)] (\(.value.description))"' "$METADATA_FILE" \
            | $GUM choose --no-limit --header "$(get_menu_text categoryMultiHeader)" --cursor="▶ " --selected.foreground="212" --cursor.foreground="212")

          if [ -z "$selected" ]; then
            return 1
          fi

          local new_model
          new_model=$(pick_model_id "$(get_menu_text modelHeaderMultiple)") || return 1

          # Check for reasoning effort
          local provider="''${new_model%%/*}"
          local model_id="''${new_model#*/}"
          local efforts
          efforts=$(get_effective_model_field "$provider" "$model_id" '.reasoning_effort // empty')

          local selected_effort=""
          if [ -n "$efforts" ]; then
            local effort_options
            effort_options=$(echo "$efforts" | $JQ -r '.[]')
            selected_effort=$(echo "$effort_options" | $GUM choose --header "$(get_menu_text reasoningEffortHeader)")
            if [ -z "$selected_effort" ]; then
              return 1
            fi
          fi

          local category_ids=()
          while IFS=$'\t' read -r category_id _; do
            [ -n "$category_id" ] && category_ids+=("$category_id")
          done <<< "$selected"

          if [ "''${#category_ids[@]}" -eq 0 ]; then
            return 1
          fi

          update_multiple_groups_state "$new_model" "$selected_effort" "''${category_ids[@]}"
          $GUM style --foreground 212 "✅ Updated ''${#category_ids[@]} categories to $new_model (effort: ''${selected_effort:-auto})"
        }

        preset_summary() {
          local preset_name="$1"
          $JQ -r --slurpfile meta "$METADATA_FILE" --arg name "$preset_name" '
            def model_of($value):
              if $value == null then "unset"
              elif ($value | type) == "object" then ($value.model // "unset")
              else $value
              end;
            (.presets[$name].categories // {}) as $cats
            | (($meta[0].categories // {}) | keys) as $keys
            | $keys
            | map("\(.):\(model_of($cats[.]))")
            | join(", ")
          ' "$PRESETS_FILE"
        }

        preset_lines() {
          ensure_presets_file

          if [ "$($JQ -r '.presets | length' "$PRESETS_FILE")" -eq 0 ]; then
            $GUM style --foreground 214 "No presets available yet. Use 'Save Current Config as Preset' first."
            return 1
          fi

          $JQ -r '.presets | keys[]' "$PRESETS_FILE" | while IFS= read -r name; do
            local summary
            summary=$(preset_summary "$name")
            printf '%s\t%s\n' "$name" "$summary"
          done
        }

        save_preset() {
          ensure_state_file
          ensure_presets_file

          local preset_name
          preset_name=$($GUM input --placeholder "$(get_menu_text presetNamePrompt)")
          if [ -z "$preset_name" ]; then
            return 1
          fi

          local safe_name
          safe_name=$(echo "$preset_name" | tr ' /' '__' | sed -E 's/[^A-Za-z0-9._-]//g')
          if [ -z "$safe_name" ]; then
            $GUM style --foreground 196 "Error: Invalid preset name"
            return 1
          fi

          if $JQ -e --arg name "$safe_name" '.presets[$name] != null' "$PRESETS_FILE" >/dev/null; then
            if ! $GUM confirm "Preset already exists. Overwrite?"; then
              return 1
            fi
          fi

          if ! $JQ --arg name "$safe_name" --argjson state "$(cat "$STATE_FILE")" '
            .presets[$name] = $state
          ' "$PRESETS_FILE" > "''${PRESETS_FILE}.tmp"; then
            $GUM style --foreground 196 "Error: Failed to save preset"
            return 1
          fi

          mv "''${PRESETS_FILE}.tmp" "$PRESETS_FILE"

          $GUM style --foreground 212 "✅ Saved preset '$safe_name'"
        }

        validate_preset_file() {
          local preset_name="$1"
          $JQ -e --arg name "$preset_name" '.presets[$name].categories | type == "object"' "$PRESETS_FILE" >/dev/null 2>&1
        }

        apply_preset() {
          local preset_name="$1"
          if ! validate_preset_file "$preset_name"; then
            $GUM style --foreground 196 "Error: Preset file is invalid"
            return 1
          fi

          if ! $JQ -r --arg name "$preset_name" '.presets[$name]' "$PRESETS_FILE" > "$STATE_FILE"; then
            $GUM style --foreground 196 "Error: Failed to apply preset"
            return 1
          fi
          rebuild_runtime_configs
          $GUM style --foreground 212 "✅ Applied preset $preset_name"
        }

        delete_preset() {
          local preset_name="$1"
          if $GUM confirm "Delete preset $preset_name?"; then
            if ! $JQ --arg name "$preset_name" 'del(.presets[$name])' "$PRESETS_FILE" > "''${PRESETS_FILE}.tmp"; then
              $GUM style --foreground 196 "Error: Failed to delete preset"
              return 1
            fi

            mv "''${PRESETS_FILE}.tmp" "$PRESETS_FILE"
            $GUM style --foreground 212 "✅ Deleted preset"
          fi
        }

        edit_preset() {
          local preset_name="$1"
          local tmp_file
          tmp_file=$(mktemp)
          local editor="''${EDITOR:-nano}"
          if ! $JQ -r --arg name "$preset_name" '.presets[$name]' "$PRESETS_FILE" > "$tmp_file"; then
            $GUM style --foreground 196 "Error: Failed to load preset"
            rm -f "$tmp_file"
            return 1
          fi

          $editor "$tmp_file"

          if ! $JQ -e '.categories | type == "object"' "$tmp_file" >/dev/null 2>&1; then
            $GUM style --foreground 196 "Error: Preset file is invalid"
            rm -f "$tmp_file"
            return 1
          fi

          if ! $JQ --arg name "$preset_name" --argjson preset "$(cat "$tmp_file")" '
            .presets[$name] = $preset
          ' "$PRESETS_FILE" > "''${PRESETS_FILE}.tmp"; then
            $GUM style --foreground 196 "Error: Failed to update preset"
            rm -f "$tmp_file"
            return 1
          fi

          mv "''${PRESETS_FILE}.tmp" "$PRESETS_FILE"
          rm -f "$tmp_file"
        }

        preset_manager() {
          while true; do
            local selection
            selection=$(preset_lines | $GUM filter --placeholder "$(get_menu_text presetManagerHeader)" --header "$(get_menu_text presetManagerHeader)")
            if [ -z "$selection" ]; then
              return 1
            fi

            local preset_name
            preset_name=$(printf '%s\n' "$selection" | cut -f1)

            local action
            action=$($GUM choose \
              "Use" \
              "Edit" \
              "Delete" \
              "Back" \
              --header "$(get_menu_text presetActionHeader): $preset_name")

            case "$action" in
              Use) apply_preset "$preset_name" ;;
              Edit) edit_preset "$preset_name" ;;
              Delete) delete_preset "$preset_name" ;;
              *) return 0 ;;
            esac
          done
        }

        replace_model_across_categories() {
          local category_lines
          category_lines=$(
            while IFS=$'\t' read -r category_id _; do
              local model_id
              model_id=$(get_group_model "$category_id")
              local model_name
              model_name=$(get_model_name "$model_id")
              printf '%s\t%s [%s]\n' "$model_id" "$model_name" "$model_id"
            done < <($JQ -r '.categories | to_entries[] | "\(.key)\t\(.value.label)"' "$METADATA_FILE")
          )

          local source_options
          source_options=$(printf '%s\n' "$category_lines" | $JQ -Rrs '
            split("\n")
            | map(select(length > 0) | split("\t"))
            | unique_by(.[0])
            | map(join("\t"))
            | .[]
          ')
          if [ -z "$source_options" ]; then
            $GUM style --foreground 214 "No models are currently assigned to categories"
            return 0
          fi

          local source_selection
          source_selection=$(printf '%s\n' "$source_options" | $GUM filter --header "$(get_menu_text replaceSourceHeader)" --placeholder "Search current category models...")
          if [ -z "$source_selection" ]; then
            return 1
          fi

          local source_model
          source_model=$(printf '%s\n' "$source_selection" | cut -f1)

          local target_model
          target_model=$(pick_model_id "$(get_menu_text replaceTargetHeader)") || return 1

          # Check for reasoning effort
          local provider="''${target_model%%/*}"
          local model_id="''${target_model#*/}"
          local efforts
          efforts=$(get_effective_model_field "$provider" "$model_id" '.reasoning_effort // empty')

          local selected_effort=""
          if [ -n "$efforts" ]; then
            local effort_options
            effort_options=$(echo "$efforts" | $JQ -r '.[]')
            selected_effort=$(echo "$effort_options" | $GUM choose --header "$(get_menu_text reasoningEffortHeader)")
            if [ -z "$selected_effort" ]; then
              return 1
            fi
          fi

          local matched_categories=()
          local total_matched=0
          while IFS=$'\t' read -r category_id _; do
            local current_model
            current_model=$(get_group_model "$category_id")
            local current_effort
            current_effort=$(get_group_reasoning_effort "$category_id")

            if [ "$current_model" = "$source_model" ]; then
               # If both model AND effort are same, we don't need to update THIS category
               # but we might update others.
               if [ "$current_model" = "$target_model" ] && [ "$current_effort" = "$selected_effort" ]; then
                 continue
               fi
               matched_categories+=("$category_id")
               total_matched=$((total_matched + 1))
            fi
          done < <($JQ -r '.categories | to_entries[] | "\(.key)\t\(.value.label)"' "$METADATA_FILE")

          if [ "''${#matched_categories[@]}" -eq 0 ]; then
            $GUM style --foreground 214 "No changes needed: categories already match target model and effort"
            return 0
          fi

          update_multiple_groups_state "$target_model" "$selected_effort" "''${matched_categories[@]}"
          $GUM style --foreground 212 "✅ Updated ''${#matched_categories[@]} categories to $target_model (effort: ''${selected_effort:-auto})"
        }

        render_state_summary() {
          local categories_summary
          categories_summary=$(
            while IFS=$'\t' read -r label category_id; do
              printf -- '- %s: %s\n' "$label" "$(get_group_model "$category_id")"
            done < <($JQ -r '.categories | to_entries[] | "\(.value.label)\t\(.key)"' "$METADATA_FILE")
          )

          printf '%s\n%s' \
            "$(get_menu_text categoryStatePrefix):" \
            "$categories_summary"
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

          sync_config_from_state
          rebuild_runtime_configs >/dev/null 2>&1 || true

          local sync_warning=""
          if [ ! -f "$MODELS_FILE" ] || [ ! -s "$MODELS_FILE" ]; then
            sync_warning=" (⚠️ Models list empty, please sync!)"
          fi

          local action
          action=$($GUM choose \
            "$(get_menu_text syncAction)$sync_warning" \
            "$(get_menu_text syncConfigAction)" \
            "$(get_menu_text changeCategoriesAction)" \
            "$(get_menu_text replaceModelAction)" \
            "$(get_menu_text presetSaveAction)" \
            "$(get_menu_text presetManageAction)" \
            "$(get_menu_text initAction)" \
            "$(get_menu_text exitAction)" \
            --header "$(get_menu_text title)
        $context_msg

        $(render_state_summary)" --cursor="▶ " --selected.foreground="212" --cursor.foreground="212")

          case "$action" in
            "$(get_menu_text syncAction)"*) sync_models ;;
            "$(get_menu_text syncConfigAction)") sync_config_from_state ;;
            "$(get_menu_text changeCategoriesAction)") choose_categories ;;
            "$(get_menu_text replaceModelAction)") replace_model_across_categories ;;
            "$(get_menu_text presetSaveAction)") save_preset ;;
            "$(get_menu_text presetManageAction)") preset_manager ;;
            "$(get_menu_text initAction)") init_project ;;
            *) exit 0 ;;
          esac
        }

        if [ $# -eq 0 ]; then tui_menu; exit 0; fi

        case "''${1:-}" in
          sync) sync_models ;;
          sync-config) sync_config_from_state 1 ;;
          init) init_project ;;
          *) echo "Usage: opencode-models [sync|sync-config|init]"; exit 1 ;;
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

      # The wrapper keeps OpenCode usable on impermanent systems by recreating
      # cache/plugin paths and syncing generated config before launch.
      opencodeInitScript = pkgs.writeShellScript "opencode-init" ''
        mkdir -p "$HOME/.local/cache/opencode/node_modules/@opencode-ai"
        mkdir -p "$HOME/.config/opencode/node_modules/@opencode-ai"
        if [ -d "$HOME/.config/opencode/node_modules/@opencode-ai/plugin" ]; then
          if [ ! -L "$HOME/.local/cache/opencode/node_modules/@opencode-ai/plugin" ]; then
            ln -sf "$HOME/.config/opencode/node_modules/@opencode-ai/plugin" \
                   "$HOME/.local/cache/opencode/node_modules/@opencode-ai/plugin"
          fi
        fi

        if command -v opencode-models >/dev/null 2>&1; then
          opencode-models sync-config >/dev/null 2>&1 || true
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

      # Bind mounts are used instead of symlinks so applications see regular
      # paths even on impermanent roots and cannot replace persistence with a
      # fresh file by accident.
      toolsPersistence = self.lib.persistence.mkPersistent {
        method = "bind";
        inherit user;
        fileName = "antigravity_tools";
        targetFile = "${homeDirectory}/.antigravity_tools";
        isDirectory = true;
      };

      opencodePersistence = self.lib.persistence.mkPersistent {
        method = "bind";
        inherit user;
        fileName = "opencode";
        targetFile = "${homeDirectory}/.local/share/opencode";
        isDirectory = true;
      };

      opencodeMemPersistence = self.lib.persistence.mkPersistent {
        method = "bind";
        inherit user;
        fileName = "opencode-mem";
        targetFile = "${homeDirectory}/.opencode-mem";
        isDirectory = true;
      };

      opencodeMemConfig = {
        storagePath = "${homeDirectory}/.opencode-mem/data";
        embeddingModel = "Xenova/nomic-embed-text-v1";
        memoryProvider = "openai-chat";
        memoryModel = state.categories.deep.model;
        memoryApiUrl = "https://cliproxyapi.${publicBaseDomain}/v1";
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

      # Setup script ensures mount targets exist before the bind mounts are
      # activated, which keeps impermanence boot ordering predictable.
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

        ".config/opencode/oh-my-opencode.jsonc" = {
          text = builtins.toJSON ohMyOpencodeConfig;
          type = "copy";
          permissions = "0600";
        };

        # Compatibility alias used by some OpenCode plugin/runtime paths.
        # Keep this synced with oh-my-opencode.jsonc to avoid stale model picks.
        ".config/opencode/oh-my-openagent.jsonc" = {
          text = builtins.toJSON ohMyOpencodeConfig;
          type = "copy";
          permissions = "0600";
        };

        ".config/opencode/skills" = {
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

        ".config/opencode/opencode-mem.jsonc" = {
          text = builtins.toJSON opencodeMemConfig;
          type = "copy";
          permissions = "0644";
        };
      };
    };
}
