#!/usr/bin/env bash
# Offline contract test for `models`; fake curl covers the optional official
# catalog because sync must not depend on credentials or network availability.
# Source: packages/models/package.nix fetch_cliproxyapi_catalog (5-second rule).
set -euo pipefail
trap 'status=$?; printf "models-offline failed at line %s: %s\n" "$LINENO" "$BASH_COMMAND" >&2; exit "$status"' ERR

models_bin="${1:?usage: $0 /path/to/models}"
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
home="$root/home"
state="$root/state"
config="$root/config"
mkdir -p "$home/.omp/agent" "$state" "$config"

cat >"$state/provider.json" <<'EOF'
{"provider":"cliproxyapi"}
EOF
cat >"$state/models.json" <<'EOF'
{"providers":{"router":{"models":{}}}}
EOF
cat >"$state/_model-local-patches.json" <<'EOF'
{}
EOF
cat >"$state/filter.json" <<'EOF'
{"version":1,"providers":{"omniroute":{"metadata":{"owned_by":{"equals":"codex"}}}}}
EOF
cat >"$state/presets.json" <<'EOF'
{"presets":{}}
EOF
cat >"$state/state.json" <<'EOF'
{"categories":{"deep":"router/zeta","pi":"router/zeta"}}
EOF
cat >"$config/opencode-base.json" <<'EOF'
{"provider":{"router":{"options":{},"models":{}}},"agent":{}}
EOF
cat >"$config/oh-my-opencode-slim-base.json" <<'EOF'
{"agents":{"build":{}}}
EOF
cat >"$config/opencode-mem-base.json" <<'EOF'
{}
EOF
cat >"$config/models-metadata.json" <<'EOF'
{"categories":{"deep":{"defaultModel":"router/zeta"},"pi":{"defaultModel":"router/zeta"}},"menu":{},"slimModelBindings":[{"path":["agents","build"],"category":"deep"}],"opencodeModelBindings":[]}
EOF
cat >"$home/.omp/agent/config.yml" <<'EOF'
unrelated: retained
modelRoles:
  deep: router/zeta
  legacyLow: router/gpt-5.5-low
  legacyTerra: router/gpt-5.6-terra-xhigh
EOF

cat >"$root/gateway.json" <<'EOF'
{"data":[{"id":"zeta","name":"Gateway Zeta"},{"id":"alpha","name":"Gateway Alpha"},{"id":"gpt-5.6-terra","name":"Gateway Terra"}]}
EOF
cat >"$root/omniroute-gateway.json" <<'EOF'
{"data":[{"id":"zeta","name":"Gateway Zeta","owned_by":"codex"},{"id":"alpha","name":"Gateway Alpha","owned_by":"other"},{"id":"gpt-5.6-terra","name":"Gateway Terra","owned_by":"codex","context_length":444}]}
EOF
cat >"$root/official.json" <<'EOF'
{"data":[{"id":"zeta","owned_by":"codex","context_length":123456,"max_completion_tokens":6543,"thinking":{"levels":["low","high"],"min":"low","max":"high"},"modalities":{"input":["text","image"],"output":["text"]},"supported_parameters":["tools"]},{"id":"alpha","owned_by":"other"},{"id":"gpt-5.6-terra","context_length":111,"max_completion_tokens":222,"thinking":{"levels":["low"]}},{"id":"official-only","context_length":999999}]}
EOF
cat >"$root/official-sparse-terra.json" <<'EOF'
{"data":[{"id":"zeta","owned_by":"codex","context_length":123456,"max_completion_tokens":6543},{"id":"alpha","owned_by":"other"},{"id":"gpt-5.6-terra","context_length":333}]}
EOF
printf '#!%s\n' "$BASH" >"$root/curl"
cat >>"$root/curl" <<'EOF'
# Use the running Nix-provided Bash directly: sandboxed checks intentionally
# lack /usr/bin/env, unlike an interactive host.
# Emulate curl's -o/-w interface only; endpoint payloads stay deterministic.
set -euo pipefail
out=
for ((i = 1; i <= $#; i++)); do
  [ "${!i}" = "-o" ] && { j=$((i + 1)); out=${!j}; }
done
url="${!#}"
if [[ "$url" == *official* ]]; then
  case "${FAKE_OFFICIAL_MODE:-ok}" in
    timeout) exit 28 ;;
    invalid) printf '{not json' > "$out" ;;
    *) cp "$FAKE_OFFICIAL_JSON" "$out" ;;
  esac
elif [[ "$url" == *omniroute* ]]; then
  cp "$FAKE_OMNIROUTE_GATEWAY_JSON" "$out"
else
  cp "$FAKE_GATEWAY_JSON" "$out"
fi
printf '200'
EOF
chmod 0755 "$root/curl"

# An explicit path isolates fixture assertions from the Nix-built default. A
# later sync without this override verifies the shipped Pi extension location.
export PI_MCP_ADAPTER_PACKAGE="$root/pi-mcp-adapter"

run_models() {
  HOME="$home" MODELS_STATE_DIR="$state" MODELS_CONFIG_DIR="$config" \
    MODELS_OPENCODE_COMPAT_CONFIG_FILE="$root/compat/opencode.json" \
    MODELS_CURL="$root/curl" CLIPROXYAPI_KEY=test-key \
    MODELS_CLIPROXYAPI_BASE_URL=https://gateway.test/v1 \
    CLIPROXYAPI_MODELS_URL=https://gateway.test/v1/models \
    OMNIROUTE_MODELS_URL=https://omniroute.test/v1/models OMNIROUTE_OPENCODE_API_KEY=test-key \
    MODELS_CLIPROXYAPI_CATALOG_URL=https://official.test/models.json \
    FAKE_GATEWAY_JSON="$root/gateway.json" FAKE_OMNIROUTE_GATEWAY_JSON="$root/omniroute-gateway.json" \
    FAKE_OFFICIAL_JSON="${FAKE_OFFICIAL_JSON:-$root/official.json}" \
    "$models_bin" "$@"
}

run_models sync
jq -e '.providers.router.models | keys == ["alpha", "gpt-5.6-terra", "zeta"]' "$state/models.json" >/dev/null
jq -e '.providers.router.models.zeta.limit == {context: 123456, output: 6543}' "$state/models.json" >/dev/null
jq -e '.providers.router.models.zeta.reasoning_effort == ["high", "low"]' "$state/models.json" >/dev/null
jq -e '.providers.router.models.zeta.modalities.input == ["image", "text"] and .providers.router.models.zeta.tool_call' "$state/models.json" >/dev/null
! jq -e '.providers.router.models["official-only"]' "$state/models.json" >/dev/null
jq -e '.providers.router.models["gpt-5.6-terra"].limit == {context: 111, output: 222}' "$state/models.json" >/dev/null
jq -e '.provider.router.models["gpt-5.6-terra"].limit == {context: 111, output: 222}' "$home/.config/opencode/config.json" >/dev/null
# Input modalities are arrays; OpenCode's `limit.input` is a numeric token
# ceiling. This must remain absent when the gateway supplied only modalities.
jq -e '.provider.router.models.zeta.limit == {context: 123456, output: 6543}' "$home/.config/opencode/config.json" >/dev/null
grep -A12 'id: "gpt-5.6-terra"' "$home/.omp/agent/models.yml" | grep -q 'contextWindow: 111'
grep -A12 'id: "gpt-5.6-terra"' "$home/.omp/agent/models.yml" | grep -q 'maxTokens: 222'
grep -q 'legacyLow: router/gpt-5.5' "$home/.omp/agent/config.yml"
grep -q 'legacyTerra: router/gpt-5.6-terra' "$home/.omp/agent/config.yml"
jq -e '.providers.router.api == "openai-responses" and .providers.router.baseUrl == "https://gateway.test/v1"' "$home/.pi/agent/models.json" >/dev/null
jq -e 'all(.providers.router.models[]; (.id | type == "string" and length > 0 and startswith("router/") | not))' "$home/.pi/agent/models.json" >/dev/null
jq -e '.providers.router.models[] | select(.id == "zeta") | .reasoning == true and .input == ["image", "text"] and .contextWindow == 123456 and .maxTokens == 6543 and .cost.input == 0' "$home/.pi/agent/models.json" >/dev/null
jq -e '.defaultProvider == "router" and .defaultModel == "zeta" and .packages == [env.PI_MCP_ADAPTER_PACKAGE] and has("model") | not' "$home/.pi/agent/settings.json" >/dev/null
jq -e '.settings.hostConfigDiscovery == "off" and .mcpServers.context7.url == "https://mcp.context7.com/mcp" and .mcpServers.github.url == "https://api.githubcopilot.com/mcp/" and .mcpServers.github.headers["X-MCP-Readonly"] == "true" and .mcpServers.github.headers["X-MCP-Toolsets"] == "context,repos,users,issues,pull_requests" and .mcpServers.exa.headers["x-api-key"] == "${EXA_API_KEY}" and .mcpServers.exa.includeTools == ["web_search_exa", "web_fetch_exa"]' "$home/.pi/agent/mcp.json" >/dev/null

# The built-in default must name the npm extension directory rather than the
# derivation root Pi cannot resolve as a module.
(
  unset PI_MCP_ADAPTER_PACKAGE
  run_models sync-config
)
jq -e '(.packages | length == 1) and (.packages[0] | endswith("/lib/node_modules/pi-mcp-adapter"))' "$home/.pi/agent/settings.json" >/dev/null

# The noninteractive union commands exercise a successful BOTH assignment and
# replacement before forcing yq failure. A failed OMP write must roll back state
# and every generated runtime/config file, not merely the YAML target.
run_models assign router/zeta high deep --omp deep
jq -e '.categories.deep == {model:"router/zeta",reasoningEffort:"high"}' "$state/state.json" >/dev/null
grep -q 'deep: router/zeta' "$home/.omp/agent/config.yml"
run_models replace-assignments router/zeta router/alpha ''
jq -e '.categories.deep == "router/alpha"' "$state/state.json" >/dev/null
grep -q 'deep: router/alpha' "$home/.omp/agent/config.yml"
before="$root/before"
mkdir "$before"
for file in "$state/state.json" "$home/.config/opencode/config.json" "$home/.config/opencode/oh-my-opencode-slim.jsonc" "$home/.config/opencode/opencode-mem.jsonc" "$home/.omp/agent/models.yml" "$home/.omp/agent/config.yml" "$root/compat/opencode.json" "$home/.pi/agent/models.json" "$home/.pi/agent/settings.json" "$home/.pi/agent/mcp.json"; do
  cp "$file" "$before/$(printf '%s' "$file" | tr / _)"
done
mkdir "$root/yq-fail"
cat >"$root/yq-fail/yq" <<EOF
#!$BASH
exit 1
EOF
chmod 0755 "$root/yq-fail/yq"
if MODELS_YQ="$root/yq-fail/yq" run_models assign router/zeta high deep --omp deep; then
  printf '%s\n' 'expected induced OMP mutation failure' >&2
  exit 1
fi
for file in "$state/state.json" "$home/.config/opencode/config.json" "$home/.config/opencode/oh-my-opencode-slim.jsonc" "$home/.config/opencode/opencode-mem.jsonc" "$home/.omp/agent/models.yml" "$home/.omp/agent/config.yml" "$root/compat/opencode.json" "$home/.pi/agent/models.json" "$home/.pi/agent/settings.json" "$home/.pi/agent/mcp.json"; do
  cmp "$file" "$before/$(printf '%s' "$file" | tr / _)"
done

# Compatibility publication is a destination-local staged write; its failure
# must restore every assignment target, including a custom compatibility path.
if MODELS_FAIL_COMPAT_PUBLISH=1 run_models assign router/zeta high deep --omp deep; then
  printf '%s\n' 'expected induced compatibility publication failure' >&2
  exit 1
fi
for file in "$state/state.json" "$home/.config/opencode/config.json" "$home/.config/opencode/oh-my-opencode-slim.jsonc" "$home/.config/opencode/opencode-mem.jsonc" "$home/.omp/agent/models.yml" "$home/.omp/agent/config.yml" "$root/compat/opencode.json" "$home/.pi/agent/models.json" "$home/.pi/agent/settings.json" "$home/.pi/agent/mcp.json"; do
  cmp "$file" "$before/$(printf '%s' "$file" | tr / _)"
done

# `select` exercises the same state validation that feeds OMO Slim generation.
run_models select deep router/zeta high
jq -e '.agents.build.model == "router/zeta" and .agents.build.variant == "high"' "$home/.config/opencode/oh-my-opencode-slim.jsonc" >/dev/null
if run_models select deep router/zeta unavailable; then
  printf '%s\n' 'expected unavailable reasoning level to be rejected' >&2
  exit 1
fi

# OMP must consume the canonical key order rather than incidental JSON ordering.
run_models sync-omp
alpha_line=$(grep -n 'id: "alpha"' "$home/.omp/agent/models.yml" | cut -d: -f1)
zeta_line=$(grep -n 'id: "zeta"' "$home/.omp/agent/models.yml" | cut -d: -f1)
[ "$alpha_line" -lt "$zeta_line" ]

# Invalid and timed-out optional catalog responses retain gateway-only sync.
FAKE_OFFICIAL_MODE=invalid run_models sync
jq -e '.providers.router.models | keys == ["alpha", "gpt-5.6-terra", "zeta"]' "$state/models.json" >/dev/null
run_models sync-config
jq -e '.provider.router.models["gpt-5.6-terra"].limit == {context: 372000, output: 128000} and .provider.router.models["gpt-5.6-terra"].reasoning_effort == ["low", "medium", "high", "xhigh", "max"]' "$home/.config/opencode/config.json" >/dev/null
run_models sync-omp
grep -A12 'id: "gpt-5.6-terra"' "$home/.omp/agent/models.yml" | grep -q 'api: openai-responses'
grep -A12 'id: "gpt-5.6-terra"' "$home/.omp/agent/models.yml" | grep -q 'reasoning: true'
FAKE_OFFICIAL_MODE=timeout run_models sync
jq -e '.providers.router.models | keys == ["alpha", "gpt-5.6-terra", "zeta"]' "$state/models.json" >/dev/null

# OmniRoute filters enriched official owned_by metadata, unlike CLIProxyAPI.
# A sparse official Terra row retains its live context and receives only the
# source-cited fallback ceiling before OmniRoute's narrow vetted fallback rule.
FAKE_OFFICIAL_JSON="$root/official-sparse-terra.json" run_models sync
run_models sync-config
jq -e '.provider.router.models["gpt-5.6-terra"].limit == {context: 333, output: 128000}' "$home/.config/opencode/config.json" >/dev/null
run_models sync-omp
grep -A12 'id: "gpt-5.6-terra"' "$home/.omp/agent/models.yml" | grep -q 'contextWindow: 333'
grep -A12 'id: "gpt-5.6-terra"' "$home/.omp/agent/models.yml" | grep -q 'maxTokens: 128000'
jq -n '{provider:"omniroute"}' >"$state/provider.json"
run_models sync
run_models sync-config
jq -e '(.provider.router.models | keys == ["gpt-5.6-terra", "zeta"]) and .provider.router.models["gpt-5.6-terra"].limit == {context: 444, output: 128000}' "$home/.config/opencode/config.json" >/dev/null
run_models sync-omp
grep -q 'id: "zeta"' "$home/.omp/agent/models.yml"
! grep -q 'id: "alpha"' "$home/.omp/agent/models.yml"
grep -A12 'id: "gpt-5.6-terra"' "$home/.omp/agent/models.yml" | grep -q 'contextWindow: 444'
grep -A12 'id: "gpt-5.6-terra"' "$home/.omp/agent/models.yml" | grep -q 'maxTokens: 128000'

# Broken mutable state fails open rather than removing all model choices.
printf '{broken json\n' >"$state/filter.json"
run_models sync-config
jq -e '.provider.router.models | keys == ["alpha", "gpt-5.6-terra", "zeta"]' "$home/.config/opencode/config.json" >/dev/null

printf '%s\n' 'models offline regression tests passed'
