#!/usr/bin/env bash
# Offline contract test for `models`; fake curl covers the optional official
# catalog because sync must not depend on credentials or network availability.
# Source: packages/models/package.nix fetch_cliproxyapi_catalog (5-second rule).
set -euo pipefail

models_bin="${1:?usage: $0 /path/to/models}"
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
home="$root/home"
state="$root/state"
config="$root/config"
mkdir -p "$home/.omp/agent" "$state" "$config"

cat > "$state/provider.json" <<'EOF'
{"provider":"cliproxyapi"}
EOF
cat > "$state/models.json" <<'EOF'
{"providers":{"router":{"models":{}}}}
EOF
cat > "$state/_model-local-patches.json" <<'EOF'
{}
EOF
cat > "$state/presets.json" <<'EOF'
{"presets":{}}
EOF
cat > "$state/state.json" <<'EOF'
{"categories":{"deep":"router/zeta"}}
EOF
cat > "$config/opencode-base.json" <<'EOF'
{"provider":{"router":{"options":{},"models":{}}},"agent":{}}
EOF
cat > "$config/oh-my-opencode-slim-base.json" <<'EOF'
{"agents":{"build":{}}}
EOF
cat > "$config/opencode-mem-base.json" <<'EOF'
{}
EOF
cat > "$config/models-metadata.json" <<'EOF'
{"categories":{"deep":{"defaultModel":"router/zeta"}},"menu":{},"slimModelBindings":[{"path":["agents","build"],"category":"deep"}],"opencodeModelBindings":[]}
EOF
cat > "$home/.omp/agent/config.yml" <<'EOF'
{}
EOF

cat > "$root/gateway.json" <<'EOF'
{"data":[{"id":"zeta","name":"Gateway Zeta"},{"id":"alpha","name":"Gateway Alpha"}]}
EOF
cat > "$root/official.json" <<'EOF'
{"data":[{"id":"zeta","context_length":123456,"max_completion_tokens":6543,"thinking":{"levels":["low","high"],"min":"low","max":"high"},"modalities":{"input":["text","image"],"output":["text"]},"supported_parameters":["tools"]},{"id":"official-only","context_length":999999}]}
EOF
printf '#!%s\n' "$BASH" > "$root/curl"
cat >> "$root/curl" <<'EOF'
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
else
  cp "$FAKE_GATEWAY_JSON" "$out"
fi
printf '200'
EOF
chmod 0755 "$root/curl"

run_models() {
  HOME="$home" MODELS_STATE_DIR="$state" MODELS_CONFIG_DIR="$config" \
    MODELS_CURL="$root/curl" CLIPROXYAPI_KEY=test-key \
    CLIPROXYAPI_MODELS_URL=https://gateway.test/v1/models \
    MODELS_CLIPROXYAPI_CATALOG_URL=https://official.test/models.json \
    FAKE_GATEWAY_JSON="$root/gateway.json" FAKE_OFFICIAL_JSON="$root/official.json" \
    "$models_bin" "$@"
}

run_models sync
jq -e '.providers.router.models | keys == ["alpha", "zeta"]' "$state/models.json" >/dev/null
jq -e '.providers.router.models.zeta.limit == {context: 123456, output: 6543}' "$state/models.json" >/dev/null
jq -e '.providers.router.models.zeta.reasoning_effort == ["high", "low"]' "$state/models.json" >/dev/null
jq -e '.providers.router.models.zeta.modalities.input == ["image", "text"] and .providers.router.models.zeta.tool_call' "$state/models.json" >/dev/null
! jq -e '.providers.router.models["official-only"]' "$state/models.json" >/dev/null

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
jq -e '.providers.router.models | keys == ["alpha", "zeta"]' "$state/models.json" >/dev/null
FAKE_OFFICIAL_MODE=timeout run_models sync
jq -e '.providers.router.models | keys == ["alpha", "zeta"]' "$state/models.json" >/dev/null

printf '%s\n' 'models offline regression tests passed'
