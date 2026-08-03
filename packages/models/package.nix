{ inputs, self, ... }:
{
  perSystem =
    { pkgs, self', ... }:
    let
      opencodeApiKey = self.secrets.OMNIROUTE_OPENCODE_API_KEY;
      piApiKey = self.secrets.OMNIROUTE_PI_API_KEY;
      cliproxyApiKey = self.secrets.CLIPROXYAPI_KEY;
      bifrostApiKey = self.secrets.BIFROST_API_KEY or "";
      modelStateDirectory = self.lib.configFiles.known.modelsStateDirectory;

      modelStateAssetsDir = pkgs.runCommand "models-state-assets" { } ''
        mkdir -p "$out"
        cp ${./models.json} "$out/models.json"
        cp ${./state.json} "$out/state.json"
        cp ${./presets.json} "$out/presets.json"
        cp ${./_model-local-patches.json} "$out/_model-local-patches.json"
        cp ${./filter.json} "$out/filter.json"
        cp ${./provider.json} "$out/provider.json"
      '';

      # The shared command keeps model discovery and runtime config generation out
      # of individual terminal modules, while env overrides let activation tests
      # point each target at copied mutable assets. Sources: OpenCode config
      # schema https://opencode.ai/docs/config/ and OMP models.yml schema
      # https://github.com/can1357/oh-my-pi/blob/main/docs/models.md.
      modelsPackage = inputs.wrappers.lib.wrapPackage {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "models" ''
          # shell
          MODELS_STATE_DIR="''${MODELS_STATE_DIR:-''${NIXCONF_CONFIG_SOURCE:-$HOME/nixconf}/${modelStateDirectory.relativePath}}"
          MODELS_FILE="$MODELS_STATE_DIR/models.json"
          STATE_FILE="$MODELS_STATE_DIR/state.json"
          PRESETS_FILE="$MODELS_STATE_DIR/presets.json"
          PATCHES_FILE="$MODELS_STATE_DIR/_model-local-patches.json"
          PROVIDER_FILE="$MODELS_STATE_DIR/provider.json"
          OPENCODE_CONFIG_FILE="$HOME/.config/opencode/config.json"
          OPENCODE_COMPAT_CONFIG_FILE="''${MODELS_OPENCODE_COMPAT_CONFIG_FILE:-$HOME/.config/opencode/opencode.json}"
          # Test-only failure injection proves assignment rollback covers the
          # separately configurable compatibility destination; unset in normal use.
          FAIL_COMPAT_PUBLISH="''${MODELS_FAIL_COMPAT_PUBLISH:-0}"
          OMO_SLIM_CONFIG_FILE="$HOME/.config/opencode/oh-my-opencode-slim.jsonc"
          OPENCODE_MEM_FILE="$HOME/.config/opencode/opencode-mem.jsonc"
          LOCAL_JSONC_FILE="$PWD/opencode.jsonc"
          MODELS_CONFIG_DIR="''${MODELS_CONFIG_DIR:-$HOME/.config/models/opencode}"
          TEMPLATES_DIR="''${MODELS_TEMPLATES_DIR:-$MODELS_CONFIG_DIR/templates}"
          OPENCODE_BASE_CONFIG_FILE="''${MODELS_BASE_CONFIG_FILE:-$MODELS_CONFIG_DIR/opencode-base.json}"
          OMO_SLIM_BASE_CONFIG_FILE="''${MODELS_OMO_SLIM_BASE_CONFIG:-$MODELS_CONFIG_DIR/oh-my-opencode-slim-base.json}"
          OPENCODE_MEM_BASE_FILE="''${MODELS_MEM_BASE_CONFIG:-$MODELS_CONFIG_DIR/opencode-mem-base.json}"
          OPENCODE_METADATA_FILE="''${MODELS_METADATA_FILE:-$MODELS_CONFIG_DIR/models-metadata.json}"
          JQ="${pkgs.jq}/bin/jq"
          GUM="${pkgs.gum}/bin/gum"
          CURL="''${MODELS_CURL:-${pkgs.curl}/bin/curl}"
          # Five seconds bounds this optional catalog request; it must never
          # prevent a gateway model sync. Source: models.router-for.me contract.
          CLIPROXYAPI_CATALOG_URL="''${MODELS_CLIPROXYAPI_CATALOG_URL:-https://models.router-for.me/models.json}"
          # yq-go edits only the selected YAML nodes, retaining document
          # comments, styles, anchors, and unrelated OMP settings. Ref:
          # https://mikefarah.gitbook.io/yq/operators/assign-update
          YQ="${pkgs.yq-go}/bin/yq"
          OMP_CONFIG_FILE="''${MODELS_OMP_CONFIG_FILE:-$HOME/.omp/agent/config.yml}"
          # Tests may inject a failing yq binary to prove rollback; normal
          # operation remains pinned to the packaged yq-go binary above.
          YQ="''${MODELS_YQ:-$YQ}"
          OMP_MODELS_FILE="''${MODELS_OMP_FILE:-$HOME/.omp/agent/models.yml}"
          ROUTER_PROVIDER_ID="router"
          ROUTER_PROVIDER_NAME="Router"
          OMP_PROVIDER_ID="''${MODELS_OMP_PROVIDER_ID:-$ROUTER_PROVIDER_ID}"
          OMP_PROVIDER_NAME="''${MODELS_OMP_PROVIDER_NAME:-$ROUTER_PROVIDER_NAME}"
          CLIPROXYAPI_KEY="''${CLIPROXYAPI_KEY:-${cliproxyApiKey}}"
          OMNIROUTE_OPENCODE_API_KEY="''${OMNIROUTE_OPENCODE_API_KEY:-${opencodeApiKey}}"
          OMNIROUTE_PI_API_KEY="''${OMNIROUTE_PI_API_KEY:-${piApiKey}}"
          BIFROST_API_KEY="''${BIFROST_API_KEY:-${bifrostApiKey}}"
          # Keep generated OMP provider metadata aligned with the NixOS module's
          # PI_STREAM_FIRST_EVENT_TIMEOUT_MS; OmniRoute can legitimately spend
          # longer than OMP's 100s default routing/cold-starting upstreams before
          # the first SSE event, but an infinite watchdog would strand sessions.
          PROVIDER_TIMEOUT_MS="''${MODELS_PROVIDER_TIMEOUT_MS:-300000}"

          log_general() { $GUM style --foreground 212 "[models:general] $*"; }
          log_opencode() { $GUM style --foreground 39 "[models:opencode] $*"; }
          log_omp() { $GUM style --foreground 141 "[models:omp] $*"; }
          log_warn() { $GUM style --foreground 214 "[models:warn] $*"; }
          log_error() { $GUM style --foreground 196 "[models:error] $*"; }

          # rename(2) is atomic only on one filesystem; state and HOME may be
          # distinct persisted mounts, so stage beside each destination.
          # Bare Pi config destinations are independently overridable for the
          # offline fixture; source: https://pi.dev/docs/latest/settings.
          PI_AGENT_DIR="''${MODELS_PI_AGENT_DIR:-$HOME/.pi/agent}"
          PI_MODELS_FILE="''${MODELS_PI_MODELS_FILE:-$PI_AGENT_DIR/models.json}"
          PI_SETTINGS_FILE="''${MODELS_PI_SETTINGS_FILE:-$PI_AGENT_DIR/settings.json}"
          PI_MCP_FILE="''${MODELS_PI_MCP_FILE:-$PI_AGENT_DIR/mcp.json}"
          # Pi resolves each settings package entry as an extension directory,
          # not a derivation root. buildNpmPackage installs this extension below
          # lib/node_modules; the bare output path makes Pi's module resolver
          # search a non-existent package.json. Source:
          # https://github.com/nicobailon/pi-mcp-adapter#readme.
          PI_MCP_ADAPTER_PACKAGE="''${PI_MCP_ADAPTER_PACKAGE:-${self'.packages.pi-mcp-adapter}/lib/node_modules/pi-mcp-adapter}"

          stage_file() {
            local destination="$1"
            mkdir -p "$(dirname "$destination")"
            mktemp "$(dirname "$destination")/.$(basename "$destination").models.XXXXXX"
          }

          publish_opencode_compat_config() {
            [ "$OPENCODE_COMPAT_CONFIG_FILE" = "$OPENCODE_CONFIG_FILE" ] && return 0
            # Stage beside the configured compatibility destination so its final
            # rename is atomic even when HOME and a test/custom destination differ.
            local tmp
            tmp=$(stage_file "$OPENCODE_COMPAT_CONFIG_FILE") || return 1
            if [ "$FAIL_COMPAT_PUBLISH" = 1 ] || ! cp "$OPENCODE_CONFIG_FILE" "$tmp" || ! chmod 0600 "$tmp" || ! mv "$tmp" "$OPENCODE_COMPAT_CONFIG_FILE"; then
              rm -f "$tmp"
              log_error "Failed to publish OpenCode compatibility config to $OPENCODE_COMPAT_CONFIG_FILE"
              return 1
            fi
          }

          ensure_provider_file() {
            ensure_repo_state_files
            if [ ! -f "$PROVIDER_FILE" ] || [ ! -s "$PROVIDER_FILE" ]; then
              printf '{"provider":"cliproxyapi"}\n' > "$PROVIDER_FILE"
            fi
          }

          get_router_provider() {
            ensure_provider_file
            local provider
            provider=$($JQ -r '.provider // "cliproxyapi"' "$PROVIDER_FILE")
            case "$provider" in
              cliproxyapi|bifrost|omniroute) printf '%s\n' "$provider" ;;
              *) printf '%s\n' "cliproxyapi" ;;
            esac
          }

          router_provider_label() {
            case "''${1:-$(get_router_provider)}" in
              cliproxyapi) printf '%s\n' "CLIProxyAPI" ;;
              bifrost) printf '%s\n' "Bifrost" ;;
              omniroute) printf '%s\n' "OmniRoute" ;;
              *) printf '%s\n' "CLIProxyAPI" ;;
            esac
          }

          router_base_url_for() {
            case "$1" in
              cliproxyapi) printf '%s\n' "''${MODELS_CLIPROXYAPI_BASE_URL:-https://cliproxyapi.${self.secrets.PUBLIC_BASE_DOMAIN}/v1}" ;;
              bifrost) printf '%s\n' "''${MODELS_BIFROST_BASE_URL:-https://bifrost.${self.secrets.PUBLIC_BASE_DOMAIN}/openai}" ;;
              omniroute) printf '%s\n' "''${MODELS_OMNIROUTE_BASE_URL:-https://omniroute.${self.secrets.PUBLIC_BASE_DOMAIN}/v1}" ;;
              *) return 1 ;;
            esac
          }

          router_models_url_for() {
            case "$1" in
              cliproxyapi) printf '%s\n' "''${CLIPROXYAPI_MODELS_URL:-https://cliproxyapi.${self.secrets.PUBLIC_BASE_DOMAIN}/v1/models}" ;;
              bifrost) printf '%s\n' "''${BIFROST_MODELS_URL:-https://bifrost.${self.secrets.PUBLIC_BASE_DOMAIN}/openai/v1/models}" ;;
              omniroute) printf '%s\n' "''${OMNIROUTE_MODELS_URL:-https://omniroute.${self.secrets.PUBLIC_BASE_DOMAIN}/v1/models}" ;;
              *) return 1 ;;
            esac
          }

          router_api_key_for() {
            case "$1" in
              cliproxyapi) printf '%s\n' "$CLIPROXYAPI_KEY" ;;
              bifrost) printf '%s\n' "$BIFROST_API_KEY" ;;
              omniroute) printf '%s\n' "$OMNIROUTE_OPENCODE_API_KEY" ;;
              *) return 1 ;;
            esac
          }

          omp_api_key_for() {
            case "$1" in
              omniroute) printf '%s\n' "$OMNIROUTE_PI_API_KEY" ;;
              *) router_api_key_for "$1" ;;
            esac
          }

          pi_api_key_for() {
            case "$1" in
              omniroute) printf '%s\n' "$OMNIROUTE_PI_API_KEY" ;;
              *) router_api_key_for "$1" ;;
            esac
          }

          get_router_base_url() {
            router_base_url_for "$(get_router_provider)"
          }

          get_router_api_key() {
            router_api_key_for "$(get_router_provider)"
          }

          ensure_repo_state_files() {
            mkdir -p "$MODELS_STATE_DIR"

            if [ ! -f "$MODELS_FILE" ]; then
              cp "${modelStateAssetsDir}/models.json" "$MODELS_FILE"
            fi

            if [ ! -f "$STATE_FILE" ]; then
              cp "${modelStateAssetsDir}/state.json" "$STATE_FILE"
            fi

            if [ ! -f "$PRESETS_FILE" ]; then
              cp "${modelStateAssetsDir}/presets.json" "$PRESETS_FILE"
            fi

            if [ ! -f "$PATCHES_FILE" ]; then
              cp "${modelStateAssetsDir}/_model-local-patches.json" "$PATCHES_FILE"
            fi

            if [ ! -f "$MODELS_STATE_DIR/filter.json" ]; then
              cp "${modelStateAssetsDir}/filter.json" "$MODELS_STATE_DIR/filter.json"
            fi

            if [ ! -f "$PROVIDER_FILE" ]; then
              cp "${modelStateAssetsDir}/provider.json" "$PROVIDER_FILE"
            fi
          }

          get_effective_models_json() {
            ensure_repo_state_files
            local router_provider
            router_provider=$(get_router_provider)

            # router-for-me catalog has verified Terra at 372k/128k with the
            # listed Responses efforts; retain this fallback when its live row is
            # unavailable or sparse. Source: https://models.router-for.me/models.json.
            $JQ -cS --arg provider_id "$ROUTER_PROVIDER_ID" --arg router_provider "$router_provider" --slurpfile patches "$PATCHES_FILE" --argjson default_output 8192 '
              # OpenCode validates limit.context + limit.output as a pair for
              # custom providers. Upstream openai-compatible placeholder uses
              # 8192 when max completion tokens are unknown.
              # Source: opencode 1.17.11 bundled provider defaults
              # Source: https://opencode.ai/docs/providers/
              def normalize_model:
                . as $model
                | ($model.context // $model.limit.context // null) as $context
                # `limit.input` is an optional token count, whereas
                # `modalities.input` is a string array. Never promote modality
                # metadata into the OpenCode limit schema. Source:
                # https://opencode.ai/docs/models/.
                | ($model.input | if type == "number" then . else null end) as $root_input
                | ($model.limit.input | if type == "number" then . else null end) as $limit_input
                | ($root_input // $limit_input) as $input
                | ($model.output // $model.limit.output // null) as $output
                | ($model | del(.context, .input, .output, .limit))
                  + (if $context != null then
                      { limit: ({ context: $context
                        , output: ($output // $default_output) }
                        + (if $input != null then { input: $input } else {} end)) }
                    else
                      {}
                    end);
              def terra_fallback:
                {
                  name: "gpt-5.6-terra",
                  reasoning: true,
                  reasoning_effort: ["low", "medium", "high", "xhigh", "max"],
                  limit: { context: 372000, output: 128000 },
                  # This is a locally vetted fallback, not a claim that every
                  # gateway row is Codex-owned. Its facts are from the Router
                  # catalog source cited above; the exact marker permits only
                  # this model through the otherwise strict OmniRoute ownership filter.
                  metadata: { catalog_source: "local-terra-fallback", vetted_omniroute_fallback: true }
                };
              def merge_terra_fallback($live):
                (terra_fallback * $live) as $merged
                # normalized_limit marks only its generic 8192 placeholder, so
                # a sparse live Terra row keeps its real context while receiving
                # the source-verified 128k ceiling rather than that placeholder.
                | if $live.metadata.limit_output_inferred == true then
                    $merged | .limit.output = terra_fallback.limit.output
                  else
                    $merged
                  end
                | del(.metadata.limit_output_inferred);
              (.providers[$provider_id].models // .providers.omniroute.models // {}) as $models
              | ($models * (($patches[0] // {}) | with_entries(select($models[.key] != null)))) as $patched
              # CLIProxyAPI v7.2.113 and OmniRoute v3.8.48 accept Responses
              # reasoning.effort; do not synthesize it for Bifrost without evidence.
              | if ($router_provider == "cliproxyapi" or $router_provider == "omniroute") then
                  # Recursive merge fills sparse/missing live rows while values
                  # present in the router-for-me official catalog remain authoritative.
                  $patched + { "gpt-5.6-terra": merge_terra_fallback($patched["gpt-5.6-terra"] // {}) }
                else
                  $patched
                end
              | map_values(normalize_model)
            ' "$MODELS_FILE" | filter_effective_models "$router_provider" "$MODELS_STATE_DIR/filter.json"
          }

          filter_effective_models() {
            local router_provider="$1"
            local filter_file="$2"
            # The mutable schema is deliberately exact and fails open: raw cache
            # metadata remains reviewable; every consumer sees this post-patch catalog.
            if $JQ -e 'type == "object" and (keys | sort == ["providers", "version"]) and .version == 1 and (.providers | type == "object") and all(.providers[]; type == "object" and (keys | sort == ["metadata"]) and (.metadata | type == "object" and (keys | sort == ["owned_by"])) and (.metadata.owned_by | type == "object" and (keys | sort == ["equals"]) and (.equals | type == "string" and length > 0)))' "$filter_file" >/dev/null 2>&1; then
              $JQ -cS --arg provider "$router_provider" --slurpfile filters "$filter_file" '($filters[0].providers[$provider].metadata.owned_by.equals? // null) as $owner | if $owner == null then . else with_entries(select(.value.metadata.owned_by? == $owner or ($provider == "omniroute" and .key == "gpt-5.6-terra" and .value.metadata.vetted_omniroute_fallback == true))) end'
            else
              log_warn "Invalid filter.json; using unfiltered catalog" >&2
              $JQ -cS .
            fi
          }

          # All consumers use this explicit order rather than JSON object order.
          ordered_effective_model_entries() {
            get_effective_models_json | $JQ -c 'to_entries | sort_by(.key)'
          }

          get_effective_model_field() {
            local provider="$1"
            local model_id="$2"
            local jq_expr="$3"

            if [ "$provider" != "$ROUTER_PROVIDER_ID" ]; then
              printf '{}\n' | $JQ -r "''${jq_expr}"
              return
            fi

            get_effective_models_json | $JQ -r --arg model_id "$model_id" "
              (.[\$model_id] // {})
              | ''${jq_expr}
            "
          }

          get_model_variant_names() {
            local provider="$1"
            local model_id="$2"

            get_effective_model_field "$provider" "$model_id" '
              if (.variants // {}) != {} then
                .variants | keys
              else
                .reasoning_effort // []
              end
            '
          }

          pick_reasoning_effort() {
            local provider="$1"
            local model_id="$2"
            local efforts
            local effort_options
            local selected_effort

            if ! efforts=$(get_model_variant_names "$provider" "$model_id"); then
              printf '%s\n' ""
              return 0
            fi

            if ! effort_options=$(printf '%s\n' "$efforts" | $JQ -r 'if type == "array" then .[] else empty end'); then
              printf '%s\n' ""
              return 0
            fi

            if [ -z "$effort_options" ]; then
              printf '%s\n' ""
              return 0
            fi

            if ! selected_effort=$(printf '%s\n' "$effort_options" | $GUM choose --header "$(get_menu_text reasoningEffortHeader)"); then
              return 1
            fi

            if [ -z "$selected_effort" ]; then
              return 1
            fi

            printf '%s\n' "$selected_effort"
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
            $JQ -r --arg key "$key" '.menu[$key]' "$OPENCODE_METADATA_FILE"
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
              $JQ -r --arg category_id "$group_id" '.categories[$category_id].defaultModel' "$OPENCODE_METADATA_FILE"
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

          slim_config_matches_state() {
            local cfg_file="$1"

            if [ ! -f "$cfg_file" ] || [ ! -s "$cfg_file" ]; then
              return 1
            fi

            local mismatch=0
            while IFS=$'\t' read -r path_json category_id; do
              local state_model
              local state_effort
              local config_model
              local config_effort
              state_model=$(get_group_model "$category_id")
              state_effort=$(get_group_reasoning_effort "$category_id")

              config_model=$($JQ -r --argjson path "$path_json" 'getpath($path).model // empty' "$cfg_file")
              config_effort=$($JQ -r --argjson path "$path_json" 'getpath($path).variant // ""' "$cfg_file")

              if [ "$state_model" != "$config_model" ] || [ "$state_effort" != "$config_effort" ]; then
                mismatch=1
                break
              fi
            done < <($JQ -r '.slimModelBindings[] | "\(.path | @json)\t\(.category)"' "$OPENCODE_METADATA_FILE")

            [ "$mismatch" -eq 0 ]
          }

          opencode_agent_config_matches_state() {
            local cfg_file="$1"

            if [ ! -f "$cfg_file" ] || [ ! -s "$cfg_file" ]; then
              return 1
            fi

            local mismatch=0
            while IFS=$'\t' read -r path_json category_id; do
              local state_model
              local state_effort
              local config_model
              local config_effort
              state_model=$(get_group_model "$category_id")
              state_effort=$(get_group_reasoning_effort "$category_id")

              config_model=$($JQ -r --argjson path "$path_json" 'getpath($path).model // empty' "$cfg_file")
              config_effort=$($JQ -r --argjson path "$path_json" 'getpath($path).variant // ""' "$cfg_file")

              if [ "$state_model" != "$config_model" ] || [ "$state_effort" != "$config_effort" ]; then
                mismatch=1
                break
              fi
            done < <($JQ -r '.opencodeModelBindings[] | "\(.path | @json)\t\(.category)"' "$OPENCODE_METADATA_FILE")

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
            config_models=$($JQ -cS --arg provider_id "$ROUTER_PROVIDER_ID" '.provider[$provider_id].models // {}' "$cfg_file")

            [ "$effective_models" = "$config_models" ]
          }

          config_file_matches_provider_metadata() {
            local cfg_file="$1"

            if [ ! -f "$cfg_file" ] || [ ! -s "$cfg_file" ]; then
              return 1
            fi

            local base_provider
            local config_provider
            base_provider=$($JQ -cS \
              --arg provider_id "$ROUTER_PROVIDER_ID" \
              --arg base_url "$(get_router_base_url)" \
              --arg api_key "$(get_router_api_key)" '
                .provider[$provider_id]
                | del(.models)
                | .name = "Router"
                | .options.baseURL = $base_url
                | .options.apiKey = $api_key
              ' "$OPENCODE_BASE_CONFIG_FILE")
            config_provider=$($JQ -cS --arg provider_id "$ROUTER_PROVIDER_ID" '.provider[$provider_id] | del(.models)' "$cfg_file")

            [ "$base_provider" = "$config_provider" ]
          }

          config_file_matches_static_base() {
            local cfg_file="$1"

            if [ ! -f "$cfg_file" ] || [ ! -s "$cfg_file" ]; then
              return 1
            fi

            local static_filter
            static_filter='
              (($meta[0].opencodeModelBindings // [])
                | map([.path + ["model"], .path + ["variant"]])
                | add // []) as $agent_model_paths
              | del(.provider.router.models)
              | del(.provider.router.options.baseURL)
              | del(.provider.router.options.apiKey)
              | delpaths($agent_model_paths)
            '

            local base_static
            local config_static
            base_static=$($JQ -cS --slurpfile meta "$OPENCODE_METADATA_FILE" "$static_filter" "$OPENCODE_BASE_CONFIG_FILE")
            config_static=$($JQ -cS --slurpfile meta "$OPENCODE_METADATA_FILE" "$static_filter" "$cfg_file")

            [ "$base_static" = "$config_static" ]
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
            if ! config_file_matches_static_base "$OPENCODE_CONFIG_FILE"; then
              # Language/LSP/formatter and other static config changes should
              # refresh ~/.config/opencode/config.json without waiting for an
              # unrelated provider/model state change.
              return 0
            fi

            if ! config_file_matches_provider_metadata "$OPENCODE_CONFIG_FILE"; then
              # Default sync check only compared model data; provider-level fixes
              # such as timeout/chunkTimeout would otherwise wait for an unrelated
              # model/state change before reaching ~/.config/opencode/config.json.
              return 0
            fi

            if ! config_file_matches_effective_models "$OPENCODE_CONFIG_FILE"; then
              return 0
            fi

            if ! slim_config_matches_state "$OMO_SLIM_CONFIG_FILE"; then
              return 0
            fi

            if ! opencode_agent_config_matches_state "$OPENCODE_CONFIG_FILE"; then
              return 0
            fi

            if ! mem_config_matches_state "$OPENCODE_MEM_FILE"; then
              return 0
            fi

            return 1
          }

          sync_opencode_config_from_state() {
            local quiet="''${1:-0}"

            if config_out_of_date; then
              rebuild_opencode_runtime_configs
              if [ "$quiet" -ne 1 ]; then
                log_opencode "Synced OpenCode + OMO Slim config from model-group state"
              fi
            fi

            publish_opencode_compat_config
          }

          sync_all_runtime_configs_from_state() {
            local quiet="''${1:-0}"

            sync_opencode_config_from_state "$quiet" || return 1
            sync_omp_models "$quiet" || return 1
            sync_pi "$quiet"
          }

          sync_config_from_state() {
            sync_all_runtime_configs_from_state "''${1:-0}"
          }

          rebuild_opencode_runtime_configs() {
            ensure_state_file

            local effective_models_file
            effective_models_file=$(stage_file "$OPENCODE_CONFIG_FILE.models")
            get_effective_models_json > "$effective_models_file"

            local opencode_tmp
            opencode_tmp=$(stage_file "$OPENCODE_CONFIG_FILE")
            $JQ --slurpfile models "$effective_models_file" \
              --arg provider_id "$ROUTER_PROVIDER_ID" \
              --arg base_url "$(get_router_base_url)" \
              --arg api_key "$(get_router_api_key)" '
              .provider[$provider_id].models = $models[0]
              | .provider[$provider_id].name = "Router"
              | .provider[$provider_id].options.baseURL = $base_url
              | .provider[$provider_id].options.apiKey = $api_key
            ' "$OPENCODE_BASE_CONFIG_FILE" > "$opencode_tmp"
            rm -f "$effective_models_file"

            local slim_tmp
            slim_tmp=$(stage_file "$OMO_SLIM_CONFIG_FILE")
            cp "$OMO_SLIM_BASE_CONFIG_FILE" "$slim_tmp"

            while IFS=$'\t' read -r path_json category_id; do
              local model
              model=$(get_group_model "$category_id")
              local effort
              effort=$(get_group_reasoning_effort "$category_id")

              local next_tmp
              next_tmp=$(stage_file "$slim_tmp.next")
              if [ -n "$effort" ]; then
                $JQ --argjson path "$path_json" --arg model "$model" --arg effort "$effort" \
                  'setpath($path + ["model"]; $model) | setpath($path + ["variant"]; $effort)' \
                  "$slim_tmp" > "$next_tmp"
              else
                $JQ --argjson path "$path_json" --arg model "$model" \
                  'setpath($path + ["model"]; $model) | delpaths([$path + ["variant"]])' \
                  "$slim_tmp" > "$next_tmp"
              fi
              mv "$next_tmp" "$slim_tmp"
            done < <($JQ -r '.slimModelBindings[] | "\(.path | @json)\t\(.category)"' "$OPENCODE_METADATA_FILE")

            while IFS=$'\t' read -r path_json category_id; do
              local model
              model=$(get_group_model "$category_id")
              local effort
              effort=$(get_group_reasoning_effort "$category_id")

              local next_tmp
              next_tmp=$(stage_file "$opencode_tmp.next")
              if [ -n "$effort" ]; then
                $JQ --argjson path "$path_json" --arg model "$model" --arg effort "$effort" \
                  'setpath($path + ["model"]; $model) | setpath($path + ["variant"]; $effort)' \
                  "$opencode_tmp" > "$next_tmp"
              else
                $JQ --argjson path "$path_json" --arg model "$model" \
                  'setpath($path + ["model"]; $model) | delpaths([$path + ["variant"]])' \
                  "$opencode_tmp" > "$next_tmp"
              fi
              mv "$next_tmp" "$opencode_tmp"
            done < <($JQ -r '.opencodeModelBindings[] | "\(.path | @json)\t\(.category)"' "$OPENCODE_METADATA_FILE")

            mkdir -p "$(dirname "$OPENCODE_CONFIG_FILE")"
            mv "$opencode_tmp" "$OPENCODE_CONFIG_FILE"
            chmod 0600 "$OPENCODE_CONFIG_FILE"
            publish_opencode_compat_config || return 1

            mkdir -p "$(dirname "$OMO_SLIM_CONFIG_FILE")"
            mv "$slim_tmp" "$OMO_SLIM_CONFIG_FILE"
            chmod 0600 "$OMO_SLIM_CONFIG_FILE"

            local mem_tmp
            mem_tmp=$(stage_file "$OPENCODE_MEM_FILE")
            $JQ --arg model "$(get_group_model "deep")" '.memoryModel = $model' "$OPENCODE_MEM_BASE_FILE" > "$mem_tmp"

            mkdir -p "$(dirname "$OPENCODE_MEM_FILE")"
            mv "$mem_tmp" "$OPENCODE_MEM_FILE"
            chmod 0644 "$OPENCODE_MEM_FILE"

          }

          fetch_cliproxyapi_catalog() {
            local catalog_file="$1"
            local status
            if ! status=$($CURL -sS -L --connect-timeout 5 --max-time 5 --retry 0 \
              -w '%{http_code}' -o "$catalog_file" -H 'Accept: application/json' "$CLIPROXYAPI_CATALOG_URL"); then
              log_warn "CLIProxyAPI official catalog unavailable; using gateway metadata"
              return 1
            fi
            case "$status" in 2*) ;; *) log_warn "CLIProxyAPI official catalog HTTP $status; using gateway metadata"; return 1 ;; esac
            # The official endpoint has shipped both a bare array and OpenAI's
            # {data:[...]} envelope; accept only a non-empty model array.
            # Source: https://models.router-for.me/models.json.
            if ! $JQ -e '(.data? // .) | type == "array" and length > 0' "$catalog_file" >/dev/null 2>&1; then
              log_warn "CLIProxyAPI official catalog is invalid; using gateway metadata"
              return 1
            fi
          }

          # Fetch models from the selected Router gateway and update models.json.
          # Rich gateways may include limits/modalities/pricing; plain OpenAI
          # compatible gateways still yield usable IDs and can be locally patched.
          sync_models() {
            local router_provider
            local api_key
            local url
            local base_url

            router_provider=$(get_router_provider)
            api_key=$(router_api_key_for "$router_provider")
            url=$(router_models_url_for "$router_provider")
            base_url=$(router_base_url_for "$router_provider")

            ensure_repo_state_files

            log_general "Fetching $(router_provider_label "$router_provider") models from $url"
            local response_file
            local temp_json
            local catalog_file
            local normalization_input
            response_file=$(mktemp)
            temp_json=$(stage_file "$MODELS_FILE")
            catalog_file=$(mktemp)
            normalization_input="$response_file"

            local http_status
            if ! http_status=$($CURL -sS -L --connect-timeout 25 --max-time 90 --retry 2 --retry-delay 1 \
              -w '%{http_code}' -o "$response_file" \
              -H "Authorization: Bearer $api_key" \
              -H "Accept: application/json" \
              "$url"); then
              $GUM style --foreground 196 "Error: Failed to reach $url"
              rm -f "$response_file" "$catalog_file" "$temp_json"
              return 1
            fi

            case "$http_status" in
              2*) ;;
              *)
                local api_error
                api_error=$($JQ -r '.error.message // .message // .error // empty' "$response_file" 2>/dev/null || true)
                $GUM style --foreground 196 "Error: Model API returned HTTP $http_status''${api_error:+: $api_error}"
                rm -f "$response_file" "$catalog_file" "$temp_json"
                return 1
                ;;
            esac

            if ! $JQ -e '.data | type == "array" and length > 0' "$response_file" >/dev/null 2>&1; then
              $GUM style --foreground 196 "Error: Model API response did not contain a non-empty data array"
              rm -f "$response_file" "$catalog_file" "$temp_json"
              return 1
            fi

            if [ "$router_provider" = "cliproxyapi" ] && fetch_cliproxyapi_catalog "$catalog_file"; then
              normalization_input=$(mktemp)
              # Preserve the gateway exposed set; source-only catalog rows are
              # metadata, never selectable models.
              if ! $JQ -S --slurpfile catalog "$catalog_file" '
                ($catalog[0].data? // $catalog[0]) as $official
                | .data |= map(
                    . as $gateway
                    | ($official | map(select((.id? | tostring) == ($gateway.id | tostring))) | .[0] // {}) as $source
                    # Preserve official ownership metadata for provider filtering;
                    # gateway IDs still exclusively decide selectable source rows.
                    | $gateway + ($source | del(.id, .object, .name))
                    | ._models_catalog_source = (if ($source | length) > 0 then "gateway+official" else "gateway" end)
                  )
              ' "$response_file" > "$normalization_input"; then
                log_warn "CLIProxyAPI official catalog is unusable; using gateway metadata"
                rm -f "$normalization_input"
                normalization_input="$response_file"
              fi
            fi

            # Normalize the rich model payload into OpenCode's model schema while
            # keeping provider metadata reviewable in models.json. Field aliases
            # cover OpenAI-compatible, OpenRouter, and gateway-enriched responses.
            if ! MODELS_SELECTED_BASE_URL="$base_url" $JQ -S '
              def number_or_null:
                if type == "number" then .
                elif type == "string" and test("^[0-9]+$") then tonumber
                else null
                end;

              def first_number($values):
                reduce $values[] as $value (null; if . != null then . else ($value | number_or_null) end);

              def clean_string_array:
                if type == "array" then
                  map(select(type == "string" and length > 0)) | unique
                elif type == "string" and length > 0 then
                  [.] | unique
                else
                  []
                end;

              def first_string_array($values):
                reduce $values[] as $value ([]; if length > 0 then . else ($value | clean_string_array) end);

              def optional_object($name; $value):
                if ($value | type) == "object" and ($value | length) > 0 then { ($name): $value } else {} end;

              def optional_value($name; $value):
                if $value == null or $value == "" then {} else { ($name): $value } end;

              # Strip known upstream transport prefixes. OmniRoute also exposes
              # openai-compatible-chat-<uuid>/vendor/model paths; collapse those
              # to catalog keys that match category state (e.g. gpt-5.4-mini).
              # Real family prefixes such as anthropic/claude-* and google/gemini-*
              # stay intact after the transport segment is removed.
              def local_model_id:
                (.id | tostring) as $id
                | ($id | split("/")) as $parts
                | ["codex", "cx", "kg", "kilo-gateway", "nvidia", "omniroute", "openrouter"] as $transport_prefixes
                | (
                    if ($parts | length) > 1 and (
                      ($transport_prefixes | index($parts[0])) != null
                      or ($parts[0] | test("^openai-compatible-chat-[0-9a-f-]+$"))
                    ) then
                      $parts[1:]
                    else
                      $parts
                    end
                  ) as $rest
                | if ($rest | length) > 1 and $rest[0] == "openai" then
                    $rest[1:] | join("/")
                  else
                    $rest | join("/")
                  end;

              def support_list:
                first_string_array([
                  .supported_parameters?,
                  .supportedParameters?,
                  .capabilities.supported_parameters?,
                  .metadata.supported_parameters?
                ]);

              def has_any($items):
                support_list as $supported
                | any($items[]; . as $item | ($supported | index($item)) != null);

              def reasoning_efforts:
                first_string_array([
                  .reasoning_effort?,
                  .reasoningEffort?,
                  .supported_reasoning_efforts?,
                  .supportedReasoningEfforts?,
                  .thinking.levels?,
                  .thinking_levels?,
                  .thinkingLevels?,
                  .capabilities.reasoning_effort?,
                  .capabilities.supported_reasoning_efforts?
                ]) as $explicit
                | if ($explicit | length) > 0 then $explicit
                  else
                    []
                  end;

              def normalized_modalities:
                first_string_array([
                  .modalities.input?,
                  .modalities.inputs?,
                  .input_modalities?,
                  .inputModalities?,
                  .architecture.input_modalities?,
                  .architecture.inputModalities?,
                  .capabilities.input_modalities?
                ]) as $input
                | first_string_array([
                  .modalities.output?,
                  .modalities.outputs?,
                  .output_modalities?,
                  .outputModalities?,
                  .architecture.output_modalities?,
                  .architecture.outputModalities?,
                  .capabilities.output_modalities?
                ]) as $output
                | (if ($input | length) > 0 then { input: $input } else {} end)
                  + (if ($output | length) > 0 then { output: $output } else {} end);

              # OpenCode model metadata treats `limit.context` as the anchor for
              # compaction/model sizing and requires paired `limit.output` on custom
              # providers. OmniRoute often returns context-only rows; fill output
              # with the upstream openai-compatible default (8192) so the cache is
              # schema-valid, and prefer vendor patches for real ceilings.
              # Source: https://opencode.ai/docs/models/
              # Source: opencode 1.17.11 bundled provider defaults
              def normalized_limit:
                first_number([
                  .limit.context?, .limits.context?, .context?, .context_length?, .contextLength?,
                  .context_window?, .contextWindow?, .max_context_length?, .maxContextLength?,
                  .top_provider.context_length?, .topProvider.contextLength?
                ]) as $context
                | first_number([
                  .limit.output?, .limits.output?, .output?, .output_tokens?, .outputTokens?,
                  .max_output_tokens?, .maxOutputTokens?, .max_completion_tokens?, .maxCompletionTokens?,
                  .top_provider.max_completion_tokens?, .topProvider.maxCompletionTokens?
                ]) as $output
                | if $context != null then
                    { context: $context, output: ($output // 8192), output_inferred: ($output == null) }
                  else
                    {}
                  end;

              def model_metadata:
                {
                  upstream_id: (.id | tostring)
                }
                + optional_value("object"; .object?)
                + optional_value("owned_by"; .owned_by? // .ownedBy?)
                + optional_value("description"; .description?)
                + optional_object("pricing"; .pricing? // {})
                + optional_object("architecture"; .architecture? // {})
                + optional_object("top_provider"; .top_provider? // .topProvider? // {})
                + optional_object("per_request_limits"; .per_request_limits? // .perRequestLimits? // {})
                + optional_value("catalog_source"; ._models_catalog_source?)
                + (support_list as $supported | if ($supported | length) > 0 then { supported_parameters: $supported } else {} end);

              def to_opencode_entry:
                (.id | tostring) as $raw_id
                | local_model_id as $key
                | normalized_limit as $limit
                | normalized_modalities as $modalities
                | reasoning_efforts as $efforts
                | support_list as $supported
                | {
                    key: $key,
                    value: ({
                      name: (.name // .display_name // .displayName // .id),
                      metadata: model_metadata
                    }
                    # Catalog key may be a short alias; keep the gateway path as
                    # wire `id` so OpenCode/OMP still request the OmniRoute model.
                    # Source: https://opencode.ai/docs/providers/
                    + (if $key != $raw_id then { id: $raw_id } else {} end)
                    + (if ($limit | length) > 0 then { limit: ($limit | del(.output_inferred)) } else {} end)
                    + (if $limit.output_inferred then { metadata: (model_metadata + { limit_output_inferred: true }) } else {} end)
                    + (if ($modalities | length) > 0 then { modalities: $modalities } else {} end)
                    + (if ($efforts | length) > 0 then { reasoning: true, reasoning_effort: $efforts } else {} end)
                    + (if ((
                      .tool_call
                      // .toolCall
                      // .tool_calling
                      // .toolCalling
                      // .supports_tools
                      // .supportsTools
                      // .supports_tool_calling
                      // .supportsToolCalling
                      // .capabilities.tool_call
                      // .capabilities.toolCall
                      // .capabilities.tool_calling
                      // .capabilities.toolCalling
                      // .capabilities.supports_tools
                      // .capabilities.supportsTools
                      // .capabilities.supports_tool_calling
                      // .capabilities.supportsToolCalling
                      // false
                    ) == true) or (($supported | index("tools")) != null) or (($supported | index("tool_choice")) != null) then { tool_call: true } else {} end))
                  };

              def effective_id:
                .value.id // .value.metadata.upstream_id // .key;

              def transport_priority:
                (effective_id | split("/")[0]) as $prefix
                | if $prefix == "codex" then 0
                  elif $prefix == "cx" then 1
                  elif $prefix == "kilo-gateway" then 2
                  elif $prefix == "kg" then 3
                  elif $prefix == "omniroute" then 4
                  elif $prefix == "openrouter" then 5
                  elif $prefix == "nvidia" then 6
                  else 7
                  end;

              def collapse_duplicate_models:
                group_by(.key)
                | map(
                    sort_by(transport_priority) as $group
                    | $group[0] as $selected
                    | ($group | map(.value.id // .value.metadata.upstream_id) | unique) as $upstream_ids
                    | $selected
                      + (if ($upstream_ids | length) > 1 then
                          {
                            value: ($selected.value + {
                              metadata: ($selected.value.metadata + {
                                alternate_upstream_ids: ($upstream_ids | map(select(. != ($selected.value.id // $selected.value.metadata.upstream_id))))
                              })
                            })
                          }
                        else
                          {}
                        end)
                  );

              ([.data[] | select((.id? // "") != "") | to_opencode_entry] | sort_by(.key, transport_priority) | collapse_duplicate_models) as $entries
              | {
                  providers: {
                    router: {
                      # Keep cache metadata aligned with the generated runtime
                      # provider in _providers.nix: one stable OpenCode provider
                      # called Router, with the concrete gateway selected by state.
                      # Match _providers.nix: native OpenAI transport selects
                      # Responses API while retaining the gateway /v1 base.
                      # Source: https://ai-sdk.dev/providers/ai-sdk-providers/openai#responses-api
                      npm: "@ai-sdk/openai",
                      name: "Router",
                      options: {
                        baseURL: env.MODELS_SELECTED_BASE_URL
                      },
                      syncedAt: (now | todateiso8601),
                      models: ($entries | from_entries)
                    }
                  }
                }
            ' "$normalization_input" > "$temp_json"; then
              $GUM style --foreground 196 "Error: Failed to normalize model metadata"
              rm -f "$response_file" "$temp_json"
              return 1
            fi

            if ! $JQ -e '.providers.router.models | type == "object" and length > 0' "$temp_json" >/dev/null; then
              $GUM style --foreground 196 "Error: Normalized model cache is empty"
              rm -f "$response_file" "$temp_json"
              return 1
            fi

            mv "$temp_json" "$MODELS_FILE"
            rm -f "$response_file" "$catalog_file"
            [ "$normalization_input" = "$response_file" ] || rm -f "$normalization_input"

            local stats
            stats=$($JQ -r '
              (.providers.router.models // {}) as $models
              | [
                  "models=\($models | length)",
                  "limits=\([$models[] | select(.limit.context? != null or .limit.output? != null)] | length)",
                  "reasoning=\([$models[] | select(.reasoning == true)] | length)",
                  "tools=\([$models[] | select(.tool_call == true)] | length)",
                  "image_output=\([$models[] | select(((.modalities.output // []) | index("image")) != null)] | length)"
                ]
              | join(", ")
            ' "$MODELS_FILE")
            log_opencode "Synced OpenCode model cache to $MODELS_FILE ($stats)"

            local missing_state_models
            missing_state_models=$($JQ -r --slurpfile state "$STATE_FILE" '
              (.providers.router.models // {}) as $models
              | (($state[0].categories // {}) | to_entries[] | .value | if type == "object" then .model else . end)
              | select(type == "string" and startswith("router/"))
              | sub("^router/"; "")
              | select($models[.] == null)
            ' "$MODELS_FILE" | sort -u)
            if [ -n "$missing_state_models" ]; then
              log_warn "OpenCode state.json references models missing from the synced cache:"
              printf '%s\n' "$missing_state_models"
            fi

            local risky_state_models
            risky_state_models=$(get_effective_models_json | $JQ -r --slurpfile state "$STATE_FILE" '
              . as $models
              | (($state[0].categories // {}) | to_entries[] | .value | if type == "object" then .model else . end)
              | select(type == "string" and startswith("router/"))
              | sub("^router/"; "") as $model_id
              | ($models[$model_id] // {}) as $model
              | [
                  (if ($model.limit.context? == null or $model.limit.output? == null) then "missing-limit" else empty end),
                  (if ($model.tool_call? != true) then "tool-call-unverified" else empty end),
                  (if (($model.modalities.output? // ["text"]) | index("text")) == null then "non-text-output" else empty end)
                ] as $issues
              | select($issues | length > 0)
              | "\($model_id): \($issues | join(", "))"
            ' | sort -u)
            if [ -n "$risky_state_models" ]; then
              # OpenCode default behavior is to accept sparse custom model metadata.
              # Warn on active category models because missing limits/tool metadata
              # can degrade compaction and agentic tool behavior without producing
              # an OmniRoute request error.
              log_warn "OpenCode active category models have sparse or risky metadata:"
              printf '%s\n' "$risky_state_models"
              log_warn "Patch verified facts in _model-local-patches.json before relying on these models for agentic work."
            fi

            log_general "Remember to git add repo state changes if you want them committed."
            sync_all_runtime_configs_from_state
          }

          # Write OMP's mutable model catalog from the effective Router cache.
          # OMP loads custom providers from ~/.omp/agent/models.yml and expects
          # contextWindow/maxTokens instead of OpenCode's limit object.
          # Source: https://github.com/can1357/oh-my-pi/blob/main/docs/models.md.
          # Provider timeout is retained for OMP versions that read generated
          # metadata; the NixOS module also exports PI_STREAM_FIRST_EVENT_TIMEOUT_MS
          # so current pi-ai stream watchdogs use the same finite first-event window.
          sync_omp_models() {
            local quiet="''${1:-0}"
            local router_provider
            local pi_api_key
            local omp_base_url
            router_provider=$(get_router_provider)
            pi_api_key="''${MODELS_OMP_API_KEY:-$(omp_api_key_for "$router_provider")}"
            omp_base_url="''${MODELS_OMP_BASE_URL:-$(router_base_url_for "$router_provider")}"
            if [ -z "$pi_api_key" ]; then
              $GUM style --foreground 196 "Error: Router API key is required for OMP model sync. Check the selected provider credential and rerun rebuild.sh."
              return 1
            fi


            ensure_repo_state_files

            local tmp
            tmp=$(stage_file "$OMP_MODELS_FILE")

            {
              printf '%s\n' '# Managed by `models sync-omp`; edit for local OMP experiments, then rerun sync when refreshing Router.'
              ordered_effective_model_entries | $JQ -r \
                --arg provider_id "$OMP_PROVIDER_ID" \
                --arg provider_name "$OMP_PROVIDER_NAME" \
                --arg base_url "$omp_base_url" \
                --arg api_key "$pi_api_key" \
                --argjson provider_timeout_ms "$PROVIDER_TIMEOUT_MS" '
                def q: @json;
                def cost:
                  (.cost // {}) as $cost
                  | (.metadata.pricing // {}) as $pricing
                  | {
                      input: (($cost.input // $pricing.prompt // $pricing.input // 0) | tonumber?),
                      output: (($cost.output // $pricing.completion // $pricing.output // 0) | tonumber?),
                      cacheRead: (($cost.cacheRead // $cost.cache_read // $pricing.cache_read // $pricing.cacheRead // 0) | tonumber?),
                      cacheWrite: (($cost.cacheWrite // $cost.cache_write // $pricing.cache_write // $pricing.cacheWrite // 0) | tonumber?)
                    };
                # OMP Responses transport sends OpenAI /v1/responses API at
                # both scopes; retain the selected gateway /v1 base URL. Source:
                # https://github.com/can1357/oh-my-pi/blob/main/docs/models.md
                "providers:\n  \($provider_id):\n    name: \($provider_name | q)\n    baseUrl: \($base_url | q)\n    apiKey: \($api_key | q)\n    api: openai-responses\n    timeoutMs: \($provider_timeout_ms)\n    models:\n" +
                (map(
                  .value as $model
                  | "      - id: \(($model.id // .key) | q)\n        name: \(($model.name // .key) | q)\n        api: openai-responses\n        provider: \($provider_id | q)\n        baseUrl: \($base_url | q)\n        input: \((($model.modalities.input // ["text"]) | map(select(. == "text" or . == "image")) | if length > 0 then . else ["text"] end) | q)\n        cost: \(($model | cost) | q)" +
                    (if $model.reasoning == true then "\n        reasoning: true" else "" end) +
                    (if $model.limit.context? != null and $model.limit.context > 0 then "\n        contextWindow: \($model.limit.context)" else "" end) +
                    (if $model.limit.output? != null then "\n        maxTokens: \($model.limit.output)" else "" end)
                ) | join("\n"))
              '
            } > "$tmp"

            mv "$tmp" "$OMP_MODELS_FILE"
            chmod 0600 "$OMP_MODELS_FILE"
            sync_omp_config_roles "$quiet" || return 1
            if [ "$quiet" -ne 1 ]; then
              log_omp "Synced OMP model catalog to $OMP_MODELS_FILE"
            fi
          }

          sync_omp_config_roles() {
            local quiet="''${1:-0}"
            if [ ! -f "$OMP_CONFIG_FILE" ]; then
              return 0
            fi

                      local needs_migration
                      if ! needs_migration=$("$YQ" -o=json '
                        [.modelRoles | select(tag == "!!map") | .[] | select(tag == "!!str") | select(
                          test("^omniroute/(codex/)?")
                          or test("^router/codex/")
                          or test("^router/GPT 5.5")
                          or test("^router/gpt-5.5:")
                          or test("^router/gpt-5[.]5-(low|medium|high|xhigh)$")
                          or test("^router/gpt-5[.]6-terra-(low|medium|high|xhigh|max)$")
                          or . == "router/gpt-5.4:mini"
                        )] | length > 0
                      ' "$OMP_CONFIG_FILE"); then
                        log_error "Failed to inspect OMP modelRoles in $OMP_CONFIG_FILE"
                        return 1
            fi
                      if [ "$needs_migration" != "true" ]; then
              return 0
            fi

            local tmp
            tmp=$(mktemp "$(dirname "$OMP_CONFIG_FILE")/.config.yml.models.XXXXXX")
            if ! cp --preserve=mode "$OMP_CONFIG_FILE" "$tmp"; then
              rm -f "$tmp"
              return 1
            fi
            if ! "$YQ" -i '
                        (.modelRoles | select(tag == "!!map") | .[] | select(tag == "!!str")) |= (
                          sub("^omniroute/codex/"; "router/")
                          | sub("^omniroute/"; "router/")
                          | sub("^router/codex/"; "router/")
                          | sub("^router/GPT 5[.]5$"; "router/gpt-5.5")
                          | sub("^router/GPT 5[.]5 [(]Low[)]$"; "router/gpt-5.5-low")
                          | sub("^router/GPT 5[.]5 [(]Medium[)]$"; "router/gpt-5.5-medium")
                          | sub("^router/GPT 5[.]5 [(]High[)]$"; "router/gpt-5.5-high")
                          | sub("^router/GPT 5[.]5 [(]xHigh[)]$"; "router/gpt-5.5-xhigh")
                          | sub("^router/gpt-5[.]5:low$"; "router/gpt-5.5-low")
                          | sub("^router/gpt-5[.]5:medium$"; "router/gpt-5.5-medium")
                          | sub("^router/gpt-5[.]5:high$"; "router/gpt-5.5-high")
                          | sub("^router/gpt-5[.]5:xhigh$"; "router/gpt-5.5-xhigh")
                          | sub("^router/gpt-5[.]4:mini$"; "router/gpt-5.4-mini")
                           # OMP modelRoles are scalar IDs; its Responses catalog
                           # has no safe per-role reasoning-effort field. Source:
                           # https://github.com/can1357/oh-my-pi/blob/main/docs/models.md.
                           | sub("^router/gpt-5[.]5-(low|medium|high|xhigh)$"; "router/gpt-5.5")
                           | sub("^router/gpt-5[.]6-terra-(low|medium|high|xhigh|max)$"; "router/gpt-5.6-terra")
                )
            ' "$tmp"; then
              rm -f "$tmp"
              return 1
            fi

            if cmp -s "$OMP_CONFIG_FILE" "$tmp"; then
              rm -f "$tmp"
              return 0
            fi

            mv "$tmp" "$OMP_CONFIG_FILE"
            chmod 0600 "$OMP_CONFIG_FILE"
            if [ "$quiet" -ne 1 ]; then
              log_omp "Migrated OMP modelRoles to Router model ids in $OMP_CONFIG_FILE"
            fi
          }

          # Generate bare Pi's three agent-local JSON documents together. Pi uses
          # `openai-responses` with a /v1 gateway base (therefore /v1/responses),
          # and pi-mcp-adapter reads mcp.json without redirecting PI_CODING_AGENT_DIR.
          # Sources: https://pi.dev/docs/latest/models, https://pi.dev/docs/latest/settings,
          # https://github.com/nicobailon/pi-mcp-adapter#readme.
          sync_pi() {
            local quiet="''${1:-0}" router_provider pi_api_key pi_base_url pi_model
            router_provider=$(get_router_provider)
            pi_api_key="''${MODELS_PI_API_KEY:-$(pi_api_key_for "$router_provider")}"
            pi_base_url="''${MODELS_PI_BASE_URL:-$(router_base_url_for "$router_provider")}"
            pi_model=$(get_group_model pi | sed 's,^router/,,' )
            if [ -z "$pi_api_key" ] || [ -z "$PI_MCP_ADAPTER_PACKAGE" ]; then
              log_error "Pi sync requires the selected Router credential and PI_MCP_ADAPTER_PACKAGE"
              return 1
            fi
            local models_tmp settings_tmp mcp_tmp
            models_tmp=$(stage_file "$PI_MODELS_FILE")
            settings_tmp=$(stage_file "$PI_SETTINGS_FILE")
            mcp_tmp=$(stage_file "$PI_MCP_FILE")
            if ! ordered_effective_model_entries | $JQ \
              --arg base_url "$pi_base_url" --arg api_key "$pi_api_key" '
                { providers: { router: {
                  baseUrl: $base_url, apiKey: $api_key, api: "openai-responses",
                  models: [ .[] | .key as $id | .value | {
                    id: $id, name: (.name // $id), api: "openai-responses",
                    # Pi expects a modality array. `limit.input`, if present,
                    # is an OpenCode token count and cannot be used here.
                    reasoning: (.reasoning // false),
                    input: ((.modalities.input // ["text"])
                      | map(select(. == "text" or . == "image"))
                      | if length > 0 then . else ["text"] end),
                    contextWindow: (.limit.context // 0), maxTokens: (.limit.output // 0),
                    cost: (.cost // { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 })
                  } ]
                } } }
              ' > "$models_tmp" \
              || ! $JQ -n --arg model "$pi_model" --arg adapter "$PI_MCP_ADAPTER_PACKAGE" '
                { defaultProvider: "router", defaultModel: $model, packages: [$adapter] }
              ' > "$settings_tmp" \
              || ! $JQ -n '
                { settings: { hostConfigDiscovery: "off" }, mcpServers: {
                  context7: { type: "http", url: "https://mcp.context7.com/mcp", lifecycle: "lazy" },
                  github: { type: "http", url: "https://api.githubcopilot.com/mcp/", lifecycle: "lazy", headers: { "X-MCP-Readonly": "true", "X-MCP-Toolsets": "context,repos,users,issues,pull_requests" } },
                  exa: { type: "http", url: "https://mcp.exa.ai/mcp?tools=web_search_exa,web_fetch_exa", lifecycle: "lazy", headers: { "x-api-key": "''${EXA_API_KEY}" }, includeTools: ["web_search_exa", "web_fetch_exa"] }
                } }
              ' > "$mcp_tmp"; then
              rm -f "$models_tmp" "$settings_tmp" "$mcp_tmp"
              return 1
            fi
            chmod 0600 "$models_tmp" "$settings_tmp" "$mcp_tmp"
            local pi_paths=("$PI_MODELS_FILE" "$PI_SETTINGS_FILE" "$PI_MCP_FILE")
            local pi_tmps=("$models_tmp" "$settings_tmp" "$mcp_tmp")
            local pi_backups=() pi_existed=() index path backup
            for path in "''${pi_paths[@]}"; do
              backup=$(stage_file "$path.backup")
              pi_backups+=("$backup")
              if [ -e "$path" ]; then cp -p "$path" "$backup"; pi_existed+=(1); else pi_existed+=(0); fi
            done
            for index in "''${!pi_paths[@]}"; do
              if ! mv "''${pi_tmps[$index]}" "''${pi_paths[$index]}"; then
                for index in "''${!pi_paths[@]}"; do
                  if [ "''${pi_existed[$index]}" = 1 ]; then mv -f "''${pi_backups[$index]}" "''${pi_paths[$index]}"; else rm -f "''${pi_paths[$index]}"; fi
                done
                return 1
              fi
            done
            rm -f "''${pi_backups[@]}"
            [ "$quiet" -eq 1 ] || log_general "Synced bare Pi config to $PI_AGENT_DIR"
          }

          omp_category_models_json() {
            if [ ! -f "$OMP_CONFIG_FILE" ]; then
              printf '{}\n'
              return 0
            fi

            # Only scalar model-role entries are editable. OMP validates
            # modelRoles as string selectors; ignore malformed local data
            # rather than rewriting it or inventing category names.
            if ! "$YQ" -o=json '.modelRoles // {}' "$OMP_CONFIG_FILE" \
              | $JQ -ce 'if type == "object" then with_entries(select(.value | type == "string")) else {} end'; then
              log_error "Failed to read OMP modelRoles from $OMP_CONFIG_FILE"
              return 1
            fi
          }

          omp_category_exists() {
            local category_id="$1"
            [ -f "$OMP_CONFIG_FILE" ] || return 1

            MODELS_OMP_CATEGORY_ID="$category_id" "$YQ" -e '
              .modelRoles | select(tag == "!!map") | has(strenv(MODELS_OMP_CATEGORY_ID))
            ' "$OMP_CONFIG_FILE" >/dev/null 2>&1
          }

          update_omp_categories() {
            local full_id="$1"
            shift

            if [ $# -eq 0 ]; then
              return 1
            fi
            if [ ! -f "$OMP_CONFIG_FILE" ]; then
              log_error "OMP config not found: $OMP_CONFIG_FILE"
              return 1
            fi

            local category_id
            for category_id in "$@"; do
              if ! omp_category_exists "$category_id"; then
                log_error "OMP model role is not declared in $OMP_CONFIG_FILE: $category_id"
                return 1
              fi
            done

            # Stage all selected role updates in the config directory. yq-go
            # retains comments/anchors while the final rename avoids a partially
            # updated config if a later selected role cannot be written.
            local tmp
            tmp=$(mktemp "$(dirname "$OMP_CONFIG_FILE")/.config.yml.models.XXXXXX")
            if ! cp --preserve=mode "$OMP_CONFIG_FILE" "$tmp"; then
              rm -f "$tmp"
              return 1
            fi

            for category_id in "$@"; do
              if ! MODELS_OMP_CATEGORY_ID="$category_id" MODELS_OMP_CATEGORY_MODEL="$full_id" "$YQ" -i '
                .modelRoles[strenv(MODELS_OMP_CATEGORY_ID)] = strenv(MODELS_OMP_CATEGORY_MODEL)
              ' "$tmp"; then
                rm -f "$tmp"
                return 1
              fi
            done

            mv "$tmp" "$OMP_CONFIG_FILE"
            chmod 0600 "$OMP_CONFIG_FILE"
          }

          apply_omp_category_models() {
            local category_models_json="$1"
            if [ ! -f "$OMP_CONFIG_FILE" ]; then
              log_error "OMP config not found: $OMP_CONFIG_FILE"
              return 1
            fi

            local category_id
            while IFS= read -r category_id; do
              if ! omp_category_exists "$category_id"; then
                log_error "OMP model role is not declared in $OMP_CONFIG_FILE: $category_id"
                return 1
              fi
            done < <(printf '%s\n' "$category_models_json" | $JQ -r 'keys[]')

            local tmp
            tmp=$(mktemp "$(dirname "$OMP_CONFIG_FILE")/.config.yml.models.XXXXXX")
            if ! cp --preserve=mode "$OMP_CONFIG_FILE" "$tmp"; then
              rm -f "$tmp"
              return 1
            fi

            while IFS=$'\t' read -r category_id model; do
              if ! MODELS_OMP_CATEGORY_ID="$category_id" MODELS_OMP_CATEGORY_MODEL="$model" "$YQ" -i '
                .modelRoles[strenv(MODELS_OMP_CATEGORY_ID)] = strenv(MODELS_OMP_CATEGORY_MODEL)
              ' "$tmp"; then
                rm -f "$tmp"
                return 1
              fi
            done < <(printf '%s\n' "$category_models_json" | $JQ -r 'to_entries[] | "\(.key)\t\(.value)"')

            mv "$tmp" "$OMP_CONFIG_FILE"
            chmod 0600 "$OMP_CONFIG_FILE"
          }

          model_id_is_available() {
                      local full_id="$1"
                      local provider="''${full_id%%/*}"
                      local model_id="''${full_id#*/}"

                      if [ "$provider" != "$ROUTER_PROVIDER_ID" ]; then
                        return 1
                      fi
                      get_effective_models_json | $JQ -e --arg model_id "$model_id" 'has($model_id)' >/dev/null
          }

          model_selection_is_valid() {
            local full_id="$1"
            local effort="$2"
            local provider="''${full_id%%/*}"
            local model_id="''${full_id#*/}"
            [ "$provider" = "$ROUTER_PROVIDER_ID" ] || return 1
            get_effective_models_json | $JQ -e --arg model_id "$model_id" --arg effort "$effort" '
              .[$model_id] as $model
              | $model != null
              | if $effort == "" then .
                else (($model.reasoning_effort // []) | index($effort) != null)
                end
            ' >/dev/null
          }

          set_omp_categories() {
                      local full_id="$1"
                      shift

                      if [ $# -eq 0 ]; then
                        log_error "Specify at least one OMP modelRoles category"
                        return 1
                      fi
                      if ! model_id_is_available "$full_id"; then
                        log_error "Model is unavailable from the current Router catalog: $full_id"
                        return 1
                      fi

                      if ! update_omp_categories "$full_id" "$@"; then
                        return 1
                      fi
                      log_omp "Updated $# OMP modelRoles categor$(if [ $# -eq 1 ]; then printf y; else printf ies; fi) to $full_id"
          }

          update_group_state() {
            local group_id="$1"
            local full_id="$2"
            local effort="$3"

            ensure_state_file
            if ! model_selection_is_valid "$full_id" "$effort"; then
              log_error "Model or reasoning level is unavailable from the current Router catalog: $full_id''${effort:+ ($effort)}"
              return 1
            fi
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
            sync_all_runtime_configs_from_state 1
          }

          update_multiple_groups_state() {
            local full_id="$1"
            local effort="$2"
            shift 2

            if [ $# -eq 0 ]; then
              return 1
            fi

            ensure_state_file
            if ! model_selection_is_valid "$full_id" "$effort"; then
              log_error "Model or reasoning level is unavailable from the current Router catalog: $full_id''${effort:+ ($effort)}"
              return 1
            fi
            local ids_json
            ids_json=$(printf '%s\n' "$@" | $JQ -Rsc 'split("\n") | map(select(length > 0))')

            local temp_state
            temp_state=$(stage_file "$STATE_FILE")
            
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
            sync_all_runtime_configs_from_state 1
          }

          # Assignment changes span repo state, generated OpenCode/OMO files and
          # OMP YAML. Validate every target before writing, then retain same-dir
          # backups so an OMP/yq or runtime-generation failure leaves no durable
          # partial assignment. This is a rollback fallback for independent
          # directories; each individual replacement remains an atomic rename.
          apply_assignments_transactionally() {
            local full_id="$1" effort="$2"
            shift 2
            local target="omo" id
            local omo_ids=() omp_ids=()
            while [ $# -gt 0 ]; do
              if [ "$1" = "--omp" ]; then target="omp"; shift; continue; fi
              if [ "$target" = "omo" ]; then omo_ids+=("$1"); else omp_ids+=("$1"); fi
              shift
            done
            [ "''${#omo_ids[@]}" -gt 0 ] || [ "''${#omp_ids[@]}" -gt 0 ] || return 1
            if [ "''${#omo_ids[@]}" -gt 0 ] && ! model_selection_is_valid "$full_id" "$effort"; then
              log_error "Model or reasoning level is unavailable from the current Router catalog: $full_id''${effort:+ ($effort)}"
              return 1
            fi
            if [ "''${#omp_ids[@]}" -gt 0 ] && ! model_id_is_available "$full_id"; then
              log_error "Model is unavailable from the current Router catalog: $full_id"
              return 1
            fi
            for id in "''${omo_ids[@]}"; do
              if ! $JQ -e --arg id "$id" '.categories[$id] != null' "$OPENCODE_METADATA_FILE" >/dev/null; then
                log_error "OpenCode category is not declared: $id"; return 1
              fi
            done
            for id in "''${omp_ids[@]}"; do
              if ! omp_category_exists "$id"; then
                log_error "OMP model role is not declared in $OMP_CONFIG_FILE: $id"; return 1
              fi
            done

            local paths=("$STATE_FILE" "$OPENCODE_CONFIG_FILE" "$OPENCODE_COMPAT_CONFIG_FILE" "$OMO_SLIM_CONFIG_FILE" "$OPENCODE_MEM_FILE" "$OMP_MODELS_FILE" "$OMP_CONFIG_FILE" "$PI_MODELS_FILE" "$PI_SETTINGS_FILE" "$PI_MCP_FILE")
            local backups=() existed=() path backup
            for path in "''${paths[@]}"; do
              backup=$(stage_file "$path.backup")
              backups+=("$backup")
              if [ -e "$path" ]; then cp -p "$path" "$backup"; existed+=(1); else existed+=(0); fi
            done
            rollback_assignments() {
              local index
              for index in "''${!paths[@]}"; do
                if [ "''${existed[$index]}" = 1 ]; then mv -f "''${backups[$index]}" "''${paths[$index]}"; else rm -f "''${paths[$index]}" "''${backups[$index]}"; fi
              done
            }
            if { [ "''${#omo_ids[@]}" -eq 0 ] || update_multiple_groups_state "$full_id" "$effort" "''${omo_ids[@]}"; } \
              && { [ "''${#omp_ids[@]}" -eq 0 ] || set_omp_categories "$full_id" "''${omp_ids[@]}"; }; then
              rm -f "''${backups[@]}"
              unset -f rollback_assignments
              return 0
            fi
            rollback_assignments
            unset -f rollback_assignments
            return 1
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
            ordered_effective_model_entries | $JQ -r '
              .[]
              | "router/\(.key)\tRouter: \(.value.name) (\(.key))"
            '
          }

          pick_model_id() {
            local header="$1"
            local lines
            local selection

            if ! lines=$(model_picker_lines); then
              $GUM style --foreground 196 "Error: Failed to load model list"
              return 1
            fi

            if [ -z "$lines" ]; then
              $GUM style --foreground 214 "No models available. Use '$(get_menu_text syncAction)' first."
              return 1
            fi

            if ! selection=$(printf '%s\n' "$lines" | $GUM filter --placeholder "Search models..." --header "$header"); then
              return 1
            fi

            if [ -z "$selection" ]; then
              return 1
            fi

            printf '%s\n' "$selection" | cut -f1
          }

          set_router_provider() {
            local provider="''${1:-}"

            if [ -z "$provider" ]; then
              local selected
              if ! selected=$(printf '%s\t%s\t%s\n' \
                "cliproxyapi" "⚡ CLIProxyAPI (default)" "$(router_base_url_for cliproxyapi)" \
                "bifrost" "🌉 Bifrost" "$(router_base_url_for bifrost)" \
                "omniroute" "🧭 OmniRoute" "$(router_base_url_for omniroute)" \
                | $GUM choose \
                  --header "Router provider: $(router_provider_label)" \
                  --cursor="▶ " \
                  --selected.foreground="212" \
                  --cursor.foreground="212"); then
                return 0
              fi

              if [ -z "$selected" ]; then
                return 0
              fi

              provider=$(printf '%s\n' "$selected" | cut -f1)
            fi

            case "$provider" in
              cliproxyapi|bifrost|omniroute) ;;
              *)
                $GUM style --foreground 196 "Error: provider must be cliproxyapi, bifrost, or omniroute"
                return 1
                ;;
            esac

            ensure_provider_file
            local tmp
            tmp=$(mktemp)
            $JQ --arg provider "$provider" '.provider = $provider' "$PROVIDER_FILE" > "$tmp"
            mv "$tmp" "$PROVIDER_FILE"

            sync_models
            $GUM style --foreground 212 "Router provider: $(router_provider_label "$provider")"
          }

          invalid_category_model_count() {
            ensure_state_file
            get_effective_models_json | $JQ -r --slurpfile state "$STATE_FILE" '
              . as $models
              | [
                  (($state[0].categories // {}) | to_entries[] | .value | if type == "object" then .model else . end)
                  | select(type == "string" and startswith("router/"))
                  | sub("^router/"; "")
                  | select($models[.] == null)
                ]
              | unique
              | length
            '
          }

          invalid_omp_category_model_count() {
            get_effective_models_json | $JQ -r --slurpfile categories <(omp_category_models_json) '
              . as $models
              | [
                  ($categories[0] // {})
                  | to_entries[].value
                  | select(type == "string" and startswith("router/"))
                  | sub("^router/"; "")
                  | select($models[.] == null)
                ]
              | unique
              | length
            '
          }

          category_picker_lines() {
            ensure_state_file
            get_effective_models_json | $JQ -r --slurpfile state "$STATE_FILE" --slurpfile meta "$OPENCODE_METADATA_FILE" '
              . as $models
              | $meta[0].categories
              | to_entries[]
              | .key as $category_id
              | ((($state[0].categories // {})[$category_id] // .value.defaultModel) | if type == "object" then .model else . end) as $model
              | ($model | sub("^router/"; "")) as $model_id
              | (if (($model | startswith("router/")) and ($models[$model_id] == null)) then "\u001b[31m✗ invalid\u001b[0m" else "\u001b[32m✓ valid\u001b[0m" end) as $status
              | "\(.key)\t\($status)  \(.value.label) [\(.key)] — \($model) (\(.value.description))"
            '
          }

          choose_categories() {
            local selected
            if ! selected=$(category_picker_lines \
              | $GUM choose \
                --no-limit \
                --header "$(get_menu_text categoryHeader)" \
                --cursor="▶ " \
                --selected.foreground="212" \
                --cursor.foreground="212"); then
              return 0
            fi

            if [ -z "$selected" ]; then
              $GUM style --foreground 214 "No categories selected. Use Space to select one or more categories, then press Enter to continue."
              return 0
            fi

            local category_ids=()
            local category_labels=()
            local category_id
            local category_label
            while IFS=$'\t' read -r category_id category_label; do
              if [ -n "$category_id" ]; then
                category_ids+=("$category_id")
                category_labels+=("$category_label")
              fi
            done <<< "$selected"

            if [ "''${#category_ids[@]}" -eq 0 ]; then
              $GUM style --foreground 214 "No valid categories selected. Use Space to select one or more categories, then press Enter to continue."
              return 0
            fi

            local new_model
            if [ "''${#category_ids[@]}" -eq 1 ]; then
              new_model=$(pick_model_id "$(get_menu_text modelHeaderPrefix) ''${category_labels[0]}") || return 0
            else
              new_model=$(pick_model_id "$(get_menu_text modelHeaderMultiple) (''${#category_ids[@]} categories)") || return 0
            fi

            local provider="''${new_model%%/*}"
            local model_id="''${new_model#*/}"
            local selected_effort=""
            selected_effort=$(pick_reasoning_effort "$provider" "$model_id") || return 0

            update_multiple_groups_state "$new_model" "$selected_effort" "''${category_ids[@]}"
            $GUM style --foreground 212 "✅ Updated ''${#category_ids[@]} categories to $new_model (effort: ''${selected_effort:-auto})"
          }

          omp_category_picker_lines() {
            get_effective_models_json | $JQ -r --slurpfile categories <(omp_category_models_json) '
              . as $models
              | ($categories[0] // {})
              | to_entries[]
              | .key as $category_id
              | .value as $model
              | ($model | sub("^router/"; "")) as $model_id
              | (if (($model | startswith("router/")) and ($models[$model_id] == null)) then "\u001b[31m✗ invalid\u001b[0m" else "\u001b[32m✓ valid\u001b[0m" end) as $status
              | "\($category_id)\t\($status)  \($category_id) — \($model)"
            '
          }

          choose_omp_categories() {
            if [ ! -f "$OMP_CONFIG_FILE" ]; then
              $GUM style --foreground 214 "No OMP config found at $OMP_CONFIG_FILE"
              return 0
            fi

            local selected
            if ! selected=$(omp_category_picker_lines \
              | $GUM choose \
                --no-limit \
                --header "🥧 Select OMP modelRoles categories to update (Space to select, Enter to confirm)" \
                --cursor="▶ " \
                --selected.foreground="141" \
                --cursor.foreground="141"); then
              return 0
            fi

            if [ -z "$selected" ]; then
              $GUM style --foreground 214 "No OMP categories selected. Use Space to select one or more categories, then press Enter to continue."
              return 0
            fi

            local category_ids=()
            local category_id
            while IFS=$'\t' read -r category_id _; do
              if [ -n "$category_id" ]; then
                category_ids+=("$category_id")
              fi
            done <<< "$selected"

            if [ "''${#category_ids[@]}" -eq 0 ]; then
              $GUM style --foreground 214 "No valid OMP categories selected."
              return 0
            fi

            local new_model
            if [ "''${#category_ids[@]}" -eq 1 ]; then
              new_model=$(pick_model_id "🤖 Select model for OMP modelRoles category ''${category_ids[0]}") || return 0
            else
              new_model=$(pick_model_id "🤖 Select model for selected OMP modelRoles categories (''${#category_ids[@]} categories)") || return 0
            fi

            set_omp_categories "$new_model" "''${category_ids[@]}" || return 1
            $GUM style --foreground 141 "✅ Updated ''${#category_ids[@]} OMP categories to $new_model"
          }

          preset_summary() {
            local preset_name="$1"
            $JQ -r --slurpfile meta "$OPENCODE_METADATA_FILE" --arg name "$preset_name" '
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

          omp_preset_summary() {
            local preset_name="$1"
            $JQ -r --arg name "$preset_name" '
              (.presets[$name].ompCategories // {})
              | to_entries
              | map("\(.key):\(.value)")
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
              local omp_summary
              summary=$(preset_summary "$name")
              omp_summary=$(omp_preset_summary "$name")
              printf '%s\tOpenCode/OMO Slim: %s | OMP: %s\n' "$name" "$summary" "''${omp_summary:-unchanged}"
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

            local omp_categories
            omp_categories=$(omp_category_models_json) || return 1

            if ! $JQ --arg name "$safe_name" --argjson state "$(cat "$STATE_FILE")" --argjson omp_categories "$omp_categories" '
              .presets[$name] = ($state + {ompCategories: $omp_categories})
            ' "$PRESETS_FILE" > "''${PRESETS_FILE}.tmp"; then
              $GUM style --foreground 196 "Error: Failed to save preset"
              return 1
            fi

            mv "''${PRESETS_FILE}.tmp" "$PRESETS_FILE"

            $GUM style --foreground 212 "✅ Saved preset '$safe_name'"
          }

          validate_preset_file() {
            local preset_name="$1"
            $JQ -e --arg name "$preset_name" '
              (.presets[$name].categories | type == "object")
              and ((.presets[$name].ompCategories? // {}) | type == "object")
              and ((.presets[$name].ompCategories? // {}) | all(.[]; type == "string"))
            ' "$PRESETS_FILE" >/dev/null 2>&1
          }

          apply_preset() {
            local preset_name="$1"
            if ! validate_preset_file "$preset_name"; then
              $GUM style --foreground 196 "Error: Preset file is invalid"
              return 1
            fi

            local omp_categories
            omp_categories=$($JQ -c --arg name "$preset_name" '.presets[$name].ompCategories? // empty' "$PRESETS_FILE") || return 1
            if [ -n "$omp_categories" ]; then
                        # Check the complete OMP slice before replacing OpenCode state;
                        # a stale preset must not result in a half-applied configuration.
                        local category_id
                        while IFS= read -r category_id; do
                          if ! omp_category_exists "$category_id"; then
                            log_error "OMP model role is not declared in $OMP_CONFIG_FILE: $category_id"
              return 1
            fi
                        done < <(printf '%s\n' "$omp_categories" | $JQ -r 'keys[]')
            fi

            local previous_state
            previous_state=$(mktemp)
            cp "$STATE_FILE" "$previous_state"
            if ! $JQ -r --arg name "$preset_name" '.presets[$name] | {categories: .categories}' "$PRESETS_FILE" > "$STATE_FILE"; then
                        rm -f "$previous_state"
              $GUM style --foreground 196 "Error: Failed to apply preset"
              return 1
            fi
            if [ -n "$omp_categories" ]; then
                        if ! apply_omp_category_models "$omp_categories"; then
                          mv "$previous_state" "$STATE_FILE"
              return 1
                        fi
            fi
            rm -f "$previous_state"
            sync_all_runtime_configs_from_state 1
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

            if ! $JQ -e '
              (.categories | type == "object")
              and ((.ompCategories? // {}) | type == "object")
              and ((.ompCategories? // {}) | all(.[]; type == "string"))
            ' "$tmp_file" >/dev/null 2>&1; then
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
              if ! selection=$(preset_lines | $GUM filter --placeholder "$(get_menu_text presetManagerHeader)" --header "$(get_menu_text presetManagerHeader)"); then
                return 0
              fi
              if [ -z "$selection" ]; then
                return 0
              fi

              local preset_name
              preset_name=$(printf '%s\n' "$selection" | cut -f1)

              local action
              if ! action=$($GUM choose \
                "Use" \
                "Edit" \
                "Delete" \
                "Back" \
                --header "$(get_menu_text presetActionHeader): $preset_name"); then
                return 0
              fi

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
              done < <($JQ -r '.categories | to_entries[] | "\(.key)\t\(.value.label)"' "$OPENCODE_METADATA_FILE")
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
            if ! source_selection=$(printf '%s\n' "$source_options" | $GUM filter --header "$(get_menu_text replaceSourceHeader)" --placeholder "Search current category models..."); then
              return 0
            fi
            if [ -z "$source_selection" ]; then
              return 0
            fi

            local source_model
            source_model=$(printf '%s\n' "$source_selection" | cut -f1)

            local target_model
            target_model=$(pick_model_id "$(get_menu_text replaceTargetHeader)") || return 0

            local provider="''${target_model%%/*}"
            local model_id="''${target_model#*/}"
            local selected_effort=""
            selected_effort=$(pick_reasoning_effort "$provider" "$model_id") || return 0

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
            done < <($JQ -r '.categories | to_entries[] | "\(.key)\t\(.value.label)"' "$OPENCODE_METADATA_FILE")

            if [ "''${#matched_categories[@]}" -eq 0 ]; then
              $GUM style --foreground 214 "No changes needed: categories already match target model and effort"
              return 0
            fi

            update_multiple_groups_state "$target_model" "$selected_effort" "''${matched_categories[@]}"
            $GUM style --foreground 212 "✅ Updated ''${#matched_categories[@]} categories to $target_model (effort: ''${selected_effort:-auto})"
          }

          assignment_picker_lines() {
            # One union table keeps the user-facing concept an assignment: OMP
            # calls them roles while OMO Slim consumes OpenCode categories. The
            # target is data on each row, not a separate decision to remember.
            ensure_state_file
            get_effective_models_json | $JQ -r \
              --slurpfile state "$STATE_FILE" \
              --slurpfile meta "$OPENCODE_METADATA_FILE" \
              --slurpfile omp <(omp_category_models_json) '
                . as $models
                | ($meta[0].categories // {}) as $omo_definitions
                | ($state[0].categories // {}) as $omo_state
                | ($omp[0] // {}) as $omp_roles
                | (($omo_definitions | keys) + ($omp_roles | keys) | unique[]) as $id
                | ($omo_definitions[$id] != null) as $has_omo
                | ($omp_roles[$id] != null) as $has_omp
                | (if $has_omo then
                     (($omo_state[$id] // $omo_definitions[$id].defaultModel)
                       | if type == "object" then .model else . end)
                   else null end) as $omo_model
                | (if $has_omp then $omp_roles[$id] else null end) as $omp_model
                | (if $has_omo and $has_omp and $omo_model == $omp_model then
                     [{ target: "both", model: $omo_model }]
                   elif $has_omo and $has_omp then
                     [{ target: "OMO Slim", model: $omo_model }, { target: "OMP", model: $omp_model }]
                   elif $has_omo then [{ target: "OMO Slim", model: $omo_model }]
                   else [{ target: "OMP", model: $omp_model }]
                   end)[]
                | .target as $target | .model as $model
                | ($model | sub("^router/"; "")) as $model_id
                | (if (($model | startswith("router/")) and ($models[$model_id] == null))
                   then "\u001b[31m✗ invalid\u001b[0m" else "\u001b[32m✓ valid\u001b[0m" end) as $status
                | (if $has_omo then ($omo_definitions[$id].label // $id) else $id end) as $label
                | "\($id)\t\($target)\t\($model)\t\($status)  \($label)"
              '
          }

          choose_assignments() {
            local selected
            if ! selected=$(assignment_picker_lines | $GUM choose \
              --no-limit \
              --header "✦ Change assignments — Assignment · Target · Current model (Space to select)" \
              --cursor="▶ " \
              --selected.foreground="212" \
              --cursor.foreground="212"); then
              return 0
            fi
            [ -n "$selected" ] || return 0

            local omo_ids=()
            local omp_ids=()
            local assignment_id target _
            while IFS=$'\t' read -r assignment_id target _; do
              [ -n "$assignment_id" ] || continue
              case "$target" in
                "OMO Slim") omo_ids+=("$assignment_id") ;;
                OMP) omp_ids+=("$assignment_id") ;;
                both) omo_ids+=("$assignment_id"); omp_ids+=("$assignment_id") ;;
              esac
            done <<< "$selected"

            if [ "''${#omo_ids[@]}" -gt 0 ]; then
              $GUM style --foreground 39 "OpenCode / OMO Slim: ''${omo_ids[*]}"
            fi
            if [ "''${#omp_ids[@]}" -gt 0 ]; then
              $GUM style --foreground 141 "OMP: ''${omp_ids[*]}"
            fi

            local new_model provider model_id selected_effort=""
            new_model=$(pick_model_id "🤖 Select the new model for the selected assignments") || return 0
            if [ "''${#omo_ids[@]}" -gt 0 ]; then
              provider="''${new_model%%/*}"
              model_id="''${new_model#*/}"
              selected_effort=$(pick_reasoning_effort "$provider" "$model_id") || return 0
            fi
            apply_assignments_transactionally "$new_model" "$selected_effort" "''${omo_ids[@]}" --omp "''${omp_ids[@]}" || return 1
            $GUM style --foreground 212 "✅ Updated ''${#omo_ids[@]} OMO Slim and ''${#omp_ids[@]} OMP assignment(s) to $new_model"
          }

          replace_model_across_assignments() {
            local assignment_models
            assignment_models=$(assignment_picker_lines | while IFS=$'\t' read -r assignment_id target model _; do
              # The first three columns are machine-stable; the fourth is the
              # visual status/label column shown in the assignment table.
              printf '%s\t%s\t%s\n' "$model" "$target" "$assignment_id"
            done)

            local source_options
            source_options=$(printf '%s\n' "$assignment_models" | $JQ -Rrs '
              split("\n") | map(select(length > 0) | split("\t"))
              | group_by(.[0])[]
              | "\(.[0][0])\t\(map(.[1]) | unique | join(", ")) — \(map(.[2]) | join(", "))"
            ')
            if [ -z "$source_options" ]; then
              $GUM style --foreground 214 "No assignments are available to replace"
              return 0
            fi

            local source_selection source_model
            if ! source_selection=$(printf '%s\n' "$source_options" | $GUM filter \
              --header "⇄ Replace model — Current model · Target · Assignments" \
              --placeholder "Search assigned models..."); then
              return 0
            fi
            [ -n "$source_selection" ] || return 0
            source_model=$(printf '%s\n' "$source_selection" | cut -f1)

            local target_model provider model_id selected_effort=""
            target_model=$(pick_model_id "🤖 Replace $source_model with") || return 0
            provider="''${target_model%%/*}"
            model_id="''${target_model#*/}"

            local omo_ids=()
            local omp_ids=()
            local model target assignment_id
            while IFS=$'\t' read -r model target assignment_id; do
              [ "$model" = "$source_model" ] || continue
              case "$target" in
                "OMO Slim") omo_ids+=("$assignment_id") ;;
                OMP) omp_ids+=("$assignment_id") ;;
                both) omo_ids+=("$assignment_id"); omp_ids+=("$assignment_id") ;;
              esac
            done <<< "$assignment_models"
            [ "''${#omo_ids[@]}" -eq 0 ] && [ "''${#omp_ids[@]}" -eq 0 ] && return 0

            if [ "''${#omo_ids[@]}" -gt 0 ]; then
              selected_effort=$(pick_reasoning_effort "$provider" "$model_id") || return 0
            fi
            apply_assignments_transactionally "$target_model" "$selected_effort" "''${omo_ids[@]}" --omp "''${omp_ids[@]}" || return 1
            $GUM style --foreground 212 "✅ Replaced $source_model across ''${#omo_ids[@]} OMO Slim and ''${#omp_ids[@]} OMP assignment(s)"
          }

          replace_assignments_noninteractive() {
            local source_model="$1" target_model="$2" effort="$3"
            local omo_ids=() omp_ids=() assignment_id target model _
            while IFS=$'\t' read -r assignment_id target model _; do
              [ "$model" = "$source_model" ] || continue
              case "$target" in
                "OMO Slim") omo_ids+=("$assignment_id") ;;
                OMP) omp_ids+=("$assignment_id") ;;
                both) omo_ids+=("$assignment_id"); omp_ids+=("$assignment_id") ;;
              esac
            done < <(assignment_picker_lines)
            [ "''${#omo_ids[@]}" -gt 0 ] || [ "''${#omp_ids[@]}" -gt 0 ] || return 0
            apply_assignments_transactionally "$target_model" "$effort" "''${omo_ids[@]}" --omp "''${omp_ids[@]}"
          }

          render_state_summary() {
            local invalid_count
            local omp_invalid_count
            invalid_count=$(invalid_category_model_count)
            omp_invalid_count=$(invalid_omp_category_model_count)

            $GUM style --foreground 39 "Router: $(router_provider_label) ($(get_router_base_url))"
            $GUM style --foreground 212 "Assignments                              Target       Current model"
            # The same rows drive the picker and dashboard, so labels, targets,
            # and validity never drift between the overview and edit workflow.
            assignment_picker_lines | while IFS=$'\t' read -r assignment_id target model detail; do
              printf '  %-40s %-12s %s  %s\n' "$assignment_id" "$target" "$model" "$detail"
            done
            if [ "$invalid_count" -gt 0 ] || [ "$omp_invalid_count" -gt 0 ]; then
              $GUM style --foreground 196 "Invalid assignments — OMO Slim: $invalid_count · OMP: $omp_invalid_count"
            else
              $GUM style --foreground 82 "All assignments point to available models"
            fi
          }

          init_project() {
            local choice
            local template_choices=()

            for template_file in "$TEMPLATES_DIR"/*.json; do
              [ -e "$template_file" ] || continue
              template_choices+=("$(basename "$template_file" .json)")
            done

            if [ "''${#template_choices[@]}" -eq 0 ]; then
              log_error "No OpenCode project templates found in $TEMPLATES_DIR"
              return 1
            fi

            if ! choice=$(printf '%s\n' "''${template_choices[@]}" | $GUM choose --header "📦 Select Project Template (initializes in $PWD)" --cursor="▶ " --selected.foreground="212" --cursor.foreground="212"); then
              echo "Operation cancelled."
              return 0
            fi

            if [ -z "$choice" ]; then echo "Operation cancelled."; return 0; fi

            if [ -f "$LOCAL_JSONC_FILE" ] || [ -f "$PWD/.opencode/config.json" ]; then
              if ! $GUM confirm "This will overwrite your existing opencode.jsonc. Continue?"; then
                echo "Operation cancelled."; return 0
              fi
            fi

            local template_file="$TEMPLATES_DIR/$choice.json"

            if [ ! -f "$template_file" ]; then echo "Error: Template not found."; return 1; fi

            cat "$template_file" > "$LOCAL_JSONC_FILE"

            $GUM style --foreground 212 --border double --align center --padding "1 2" "✨ Project Initialized ✨" "Template: $choice" "Saved to: opencode.jsonc"
          }

          tui_menu() {
            while true; do
              local context_msg="Context: Global"
              if [ -f "$LOCAL_JSONC_FILE" ]; then context_msg="Context: Local Project ($LOCAL_JSONC_FILE)"; fi

              sync_all_runtime_configs_from_state 1

              local sync_warning=""
              if [ ! -f "$MODELS_FILE" ] || [ ! -s "$MODELS_FILE" ]; then
                sync_warning=" (⚠️ Models list empty, please sync!)"
              fi

              local invalid_count
              local invalid_suffix
              local omp_invalid_count
              invalid_count=$(invalid_category_model_count)
              omp_invalid_count=$(invalid_omp_category_model_count)
              if [ "$invalid_count" -gt 0 ]; then
                invalid_suffix=" ($invalid_count Invalid)"
              else
                invalid_suffix=" (0 Invalid)"
              fi

              local action
              if ! action=$($GUM choose \
                "$(get_menu_text syncAction)$sync_warning" \
                "$(get_menu_text syncConfigAction)" \
                "$(get_menu_text providerAction)" \
                "✦ Change assignments$invalid_suffix" \
                "⇄ Replace model across assignments" \
                "✦ Save current assignments as preset" \
                "✦ Browse presets" \
                "$(get_menu_text initAction)" \
                "$(get_menu_text syncOmpAction)" \
                "$(get_menu_text exitAction)" \
                --header "$(get_menu_text title)
          $context_msg

          $(render_state_summary)" --cursor="▶ " --selected.foreground="212" --cursor.foreground="212"); then
                return 0
              fi

              case "$action" in
                "$(get_menu_text syncAction)"*) sync_models || true ;;
                "$(get_menu_text syncConfigAction)") sync_config_from_state || true ;;
                "$(get_menu_text providerAction)") set_router_provider || true ;;
                "✦ Change assignments"*) choose_assignments || true ;;
                "⇄ Replace model across assignments") replace_model_across_assignments || true ;;
                "✦ Save current assignments as preset") save_preset || true ;;
                "✦ Browse presets") preset_manager || true ;;
                "$(get_menu_text initAction)") init_project || true ;;
                "$(get_menu_text syncOmpAction)") sync_omp_models || true ;;
                "$(get_menu_text exitAction)") return 0 ;;
                *) return 0 ;;
              esac
            done
          }

          usage() {
            printf '%s\n' 'Usage: models [sync|sync-all|sync-opencode|sync-config|sync-omp|select <category> <router/model> [reasoning-level]|assign <router/model> <reasoning-level> <omo-category...> --omp <omp-role...>|replace-assignments <from> <to> [reasoning-level]|omp-categories <router/model> <model-role...>|preset-apply <name>|provider|init]'
          }

          if [ $# -eq 0 ]; then tui_menu; exit 0; fi

          case "''${1:-}" in
            sync) sync_models ;;
            sync-all) sync_all_runtime_configs_from_state ;;
            sync-opencode) sync_opencode_config_from_state ;;
            sync-config) sync_config_from_state 1 ;;
            sync-omp) sync_omp_models ;;
            select) update_group_state "''${2:-}" "''${3:-}" "''${4:-}" ;;
            # Noninteractive test/automation interface: IDs before --omp are
            # OpenCode categories and IDs after it are OMP modelRoles.
            assign) apply_assignments_transactionally "''${2:-}" "''${3:-}" "''${@:4}" ;;
            replace-assignments) replace_assignments_noninteractive "''${2:-}" "''${3:-}" "''${4:-}" ;;
            omp-categories) set_omp_categories "''${2:-}" "''${@:3}" ;;
            preset-apply) apply_preset "''${2:-}" ;;
            provider) set_router_provider "''${2:-}" ;;
            init) init_project ;;
            -h|--help) usage ;;
            *) usage >&2; exit 1 ;;
          esac
        '';
      };
    in
    {
      packages.models = modelsPackage;

      # Keep this fixture-driven HTTP contract offline: the harness replaces curl
      # and invokes the built wrapper, covering the shipped command rather than a
      # copied shell fragment. Source: packages/models/tests/models-offline.sh.
      checks.models-offline =
        pkgs.runCommandLocal "models-offline"
          {
            nativeBuildInputs = [
              pkgs.bash
              pkgs.coreutils
              pkgs.gnugrep
              pkgs.jq
            ];
          }
          ''
            ${pkgs.bash}/bin/bash ${./tests/models-offline.sh} ${modelsPackage}/bin/models
            mkdir -p "$out"
          '';

      packages.m = inputs.wrappers.lib.wrapPackage {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "m" ''
          exec ${self'.packages.models}/bin/models "$@"
        '';
      };
    };
}
