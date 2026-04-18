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
      homeDirectory = config.preferences.paths.homeDirectory;
      configDirectory = config.preferences.paths.configDirectory;
      languages = import ./_languages.nix { inherit pkgs self; };
      providers = import ./_providers.nix {
        inherit self lib;
      };
      pluginsConfig = import ./_plugins.nix;
      categoriesConfig = import ./_categories.nix { inherit lib; };
      opencode = pkgs.unstable.opencode;

      # Path to the persistent model selections
      stateFile = ./state.json;
      state = categoriesConfig.mkState { inherit stateFile; };

      mcpConfig = import ./_mcp.nix {
        inherit inputs self pkgs;
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

      runtimeAssets = import ./_runtime-assets.nix {
        inherit
          pkgs
          lib
          initialConfig
          ohMyOpencodeConfig
          opencodeModelsMetadata
          mcpConfig
          ;
      };
      inherit (runtimeAssets)
        configVariantsDir
        mcpTemplates
        runtimeConfigDir
        stateAssetsDir
        ;

      # TUI for model/profile and template switching
      opencodeModelSwitch = pkgs.writeShellScriptBin "opencode-models" ''
        # shell
        REPO_DIR="${configDirectory}/modules/nixos/terminal/opencode"
        MODELS_FILE="$REPO_DIR/models.json"
        STATE_FILE="$REPO_DIR/state.json"
        PRESETS_FILE="$REPO_DIR/presets.json"
        GLOBAL_CONFIG_FILE="$HOME/.config/opencode/config.json"
        GLOBAL_OMA_FILE="$HOME/.config/opencode/oh-my-opencode.jsonc"
        # Compatibility alias used by some OpenCode/Oh-My-* plugin paths.
        # Keep both files in sync so runtime cannot silently read stale models.
        GLOBAL_OPENAGENT_FILE="$HOME/.config/opencode/oh-my-openagent.jsonc"
        LOCAL_JSONC_FILE="$PWD/opencode.jsonc"
        TEMPLATES_DIR="${configVariantsDir}/templates"
        BASE_CONFIG_FILE="${runtimeConfigDir}/opencode-base.json"
        BASE_OMA_FILE="${runtimeConfigDir}/oh-my-opencode-base.json"
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

        config_out_of_date() {
          ensure_state_file
          if ! config_file_matches_state "$GLOBAL_OMA_FILE"; then
            return 0
          fi

          if ! config_file_matches_state "$GLOBAL_OPENAGENT_FILE"; then
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

          local opencode_tmp
          opencode_tmp=$(mktemp)
          cp "$BASE_CONFIG_FILE" "$opencode_tmp"

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

        }

        # Fetch models from CliProxyApi and update models.json
        sync_models() {
          local api_key="${self.secrets.CLIPROXYAPI_KEY}"
          local url="http://localhost:8317/v1beta/models"
          
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
          name=$($JQ -r --arg provider "$provider" --arg model_id "$model_id" '.providers[$provider].models[$model_id].name // empty' "$MODELS_FILE")
          if [ -n "$name" ]; then
            printf '%s\n' "$name"
          else
            printf '%s\n' "$model_id"
          fi
        }

        model_picker_lines() {
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
          efforts=$($JQ -r --arg provider "$provider" --arg model_id "$model_id" '.providers[$provider].models[$model_id].reasoning_effort // empty' "$MODELS_FILE")

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
          $JQ -r --argfile meta "$METADATA_FILE" --arg name "$preset_name" '
            def model_of($value):
              if $value == null then "unset"
              elif ($value | type) == "object" then ($value.model // "unset")
              else $value
              end;
            (.presets[$name].categories // {}) as $cats
            | ($meta.categories | keys) as $keys
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
          efforts=$($JQ -r --arg provider "$provider" --arg model_id "$model_id" '.providers[$provider].models[$model_id].reasoning_effort // empty' "$MODELS_FILE")

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

      runtime = import ./_runtime.nix {
        inherit pkgs opencode languages;
      };
      inherit (runtime) opencodeWrapped;

      configFile = ".config/opencode/config.json";
      persistence = import ./_persistence.nix {
        inherit self user homeDirectory;
      };
      hjemFiles = import ./_hjem-files.nix {
        inherit
          user
          configFile
          initialConfig
          ohMyOpencodeConfig
          opencodeMemConfig
          ;
      };

      opencodeMemConfig = {
        storagePath = "${homeDirectory}/.opencode-mem/data";
        embeddingModel = "Xenova/nomic-embed-text-v1";
        memoryProvider = "openai-chat";
        memoryModel = state.categories.deep.model;
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
        text = persistence.activationText;
        deps = [ "users" ];
      };

      fileSystems = persistence.fileSystems;

      hjem.users = hjemFiles;
    };
}
