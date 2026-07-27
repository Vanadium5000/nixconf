#!/usr/bin/env bash
set -euo pipefail
shopt -s expand_aliases

# Simplified NixOS Rebuild Script
# Core features: Secret loading, colored logging, basic rebuild actions
# Optional features: Controlled by command-line flags

# Use custom QuickShell menu for askpass
QS_CMD='/run/current-system/sw/bin/qs-askpass'
if command -v "$QS_CMD" &>/dev/null; then
 export SUDO_ASKPASS="$QS_CMD"
 alias sudo='sudo -A'
fi

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLAKE_DIR="${SCRIPT_DIR}"
# Keep flake evaluation anchored to this checkout even when the wrapper is invoked
# from another directory. `path:` includes generated files such as secrets.nix.
FLAKE_REF="path:${FLAKE_DIR}"
HOST="${HOST:-}"
ARGS="${ARGS:-} --accept-flake-config"
# Reuse a fast SSH control connection during remote deploys and avoid wasting CPU on recompressing Nix store data in transit.
export NIX_SSHOPTS="-o Compression=no \
                   -o Ciphers=chacha20-poly1305@openssh.com \
                   -o ControlMaster=auto \
                   -o ControlPersist=60s"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Default options (all optional features off)
LOG_FILE=""
GIT_BACKUP=false
VALIDATE=false
BACKUP=false
NOTIFY=true
NOTIFIED_ERROR=false
DEBUG=false
TRACE=false
SKIP_SECRETS=false
SKIP_MATRIX=false
SKIP_LINT=false
CLEANUP_QUIET=false
REMAINING_ARGS=()
SCRIPT_START_MS=0
LAST_SECTION_MS=0
declare -a NIX_ARGS=()

now_ms() {
 local epoch="${EPOCHREALTIME:-}"
 if [[ "$epoch" == *.* ]]; then
  local seconds="${epoch%.*}"
  local fraction="${epoch#*.}"
  fraction="${fraction}000"
  printf '%s%s' "$seconds" "${fraction:0:3}"
 else
  printf '%(%s)T000' -1
 fi
}

format_duration_ms() {
 local ms="${1:-0}"
 if ((ms < 1000)); then
  printf '%dms' "$ms"
 elif ((ms < 60000)); then
  printf '%d.%03ds' $((ms / 1000)) $((ms % 1000))
 else
  printf '%dm %02d.%03ds' $((ms / 60000)) $(((ms / 1000) % 60)) $((ms % 1000))
 fi
}

timestamp() {
 printf '%(%Y-%m-%d %H:%M:%S)T' -1
}

strip_color() {
 local value="$1"
 value="${value//$RED/}"
 value="${value//$GREEN/}"
 value="${value//$YELLOW/}"
 value="${value//$BLUE/}"
 value="${value//$MAGENTA/}"
 value="${value//$CYAN/}"
 value="${value//$DIM/}"
 value="${value//$BOLD/}"
 value="${value//$NC/}"
 printf '%s' "$value"
}

emit_line() {
 local line="$1"
 local stream="${2:-stdout}"
 if [ -n "$LOG_FILE" ]; then
  printf '%b\n' "$line"
  printf '%s\n' "$(strip_color "$line")" >>"$LOG_FILE"
 elif [ "$stream" = "stderr" ]; then
  printf '%b\n' "$line" >&2
 else
  printf '%b\n' "$line"
 fi
}

# Logging functions
log() {
 local msg="$*"
 local now total
 now="$(now_ms)"
 total=$((now - SCRIPT_START_MS))
 emit_line "${BLUE}[$(timestamp) +$(format_duration_ms "$total")]${NC} $msg"
}

debug_log() {
 if [ "$DEBUG" = true ]; then
  emit_line "${DIM}[DEBUG]${NC} $*"
 fi
}

section() {
 local title="$*"
 local now total delta
 now="$(now_ms)"
 if ((SCRIPT_START_MS == 0)); then
  SCRIPT_START_MS="$now"
 fi
 if ((LAST_SECTION_MS == 0)); then
  LAST_SECTION_MS="$SCRIPT_START_MS"
 fi
 total=$((now - SCRIPT_START_MS))
 delta=$((now - LAST_SECTION_MS))
 printf '\n'
 emit_line "${CYAN}╭─ ${BOLD}${title}${NC} ${DIM}$(timestamp) total $(format_duration_ms "$total") section +$(format_duration_ms "$delta")${NC}"
 emit_line "${DIM}$(matrix_print_rule 88)${NC}"
 LAST_SECTION_MS="$now"
}

send_notification() {
 local level="$1"
 local title="$2"
 local msg="$3"
 if [ "$NOTIFY" = true ] && command_exists notify-send; then
  local icon="dialog-information"
  case "$level" in
  "error") icon="dialog-error" ;;
  "warning") icon="dialog-warning" ;;
  "success") icon="emblem-success" ;;
  esac
  # Determine if we are in a graphical environment
  if [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ]; then
   notify-send -t 5000 -u normal -i "$icon" "$title" "$msg"
  fi
 fi
}

# Enhanced logging for commands
log_command() {
 local cmd="$*"
 log "Executing: $cmd"
}

error() {
 emit_line "${RED}[ERROR]${NC} $*" stderr
 send_notification "error" "NixOS Rebuild Error" "$*"
 NOTIFIED_ERROR=true
}

success() {
 local msg="$*"
 emit_line "${GREEN}[SUCCESS]${NC} $msg"
}

warn() {
 local msg="$*"
 emit_line "${YELLOW}[WARNING]${NC} $msg" stderr
}

# Check if command exists
command_exists() {
 command -v "$1" >/dev/null 2>&1
}

refresh_nix_args() {
 NIX_ARGS=(--impure)
 if [ -n "$ARGS" ]; then
  local -a extra_args=()
  read -r -a extra_args <<<"$ARGS"
  NIX_ARGS+=("${extra_args[@]}")
 fi
}

run_cmd() {
 log_command "$*"
 "$@"
}

run_sudo() {
 log_command "sudo $*"
 sudo "$@"
}

# Secrets configuration - easily extensible associative array
# Format: ["env_var_name"]="password_store_path"
declare -A SECRETS_MAP=(
 ["PASSWORD_HASH"]="system/matrix/hashedPassword"
 ["IONOS_API_KEY"]="system/ionos-api-key"
 ["PUBLIC_BASE_DOMAIN"]="system/public-base-domain"
 ["MONGODB_PASSWORD"]="system/mongodb_password"
 ["MONGO_EXPRESS_PASSWORD"]="system/mongo_express_password"
 ["CLIPROXYAPI_KEY"]="system/cliproxyapi-key"
 ["BIFROST_ENCRYPTION_KEY"]="system/bifrost/encryption-key"
 ["BIFROST_API_KEY"]="system/bifrost/api-key"
 ["OMNIROUTE_OPENCODE_API_KEY"]="system/omniroute/opencode-api-key"
 ["OMNIROUTE_PI_API_KEY"]="system/omniroute/pi-api-key"
 ["EXA_API_KEY"]="system/exa-api-key"
 ["MITMPROXY_CA_KEY"]="system/mitmproxy-ca-key"
 ["MITMPROXY_CA_CERT"]="system/mitmproxy-ca-cert"
 ["MITMPROXY_WEB_PASSWORD"]="system/mitmproxy/web-password"
 ["OMNIROUTE_INITIAL_PASSWORD"]="system/omniroute/initial-password"
 ["VPN_PROXY_API_KEY"]="system/vpn-proxy-api-key"
 ["SERVICES_AUTH_PASSWORD"]="system/services-auth-password"
 ["MAIN_VPS_INITRD_SSH_HOST_KEY"]="system/main-vps/initrd-ssh-host-ed25519-key"
 ["DOKPLOY_AUTH_SECRET"]="system/dokploy/auth-secret"
 ["COCKPIT_ADMIN_HASHED_PASSWORD"]="system/cockpit-admin"
 ["PIA_OPENVPN_USERNAME"]="personal/private-internet-access"
 ["PIA_OPENVPN_PASSWORD"]="personal/private-internet-access"
 ["PORTAINER_ADMIN_USERNAME"]="system/portainer-admin"
 ["PORTAINER_ADMIN_PASSWORD"]="system/portainer-admin"
 ["PORTAINER_API_KEY"]="system/portainer-api-key"
 ["QBITTORRENT_WEBUI_USERNAME"]="personal/qbittorrent-webui"
 ["QBITTORRENT_WEBUI_PASSWORD"]="personal/qbittorrent-webui"
)

# Credential field parsing is opt-in: entries listed here are parsed as
# password-store credential records, and all other secret paths are consumed as
# raw `pass show` output. Declare every field-backed credential explicitly so a
# multi-field entry cannot silently replace a raw secret.
# Format: ["env_var_name"]="credential_field_name"
declare -A SECRET_FIELDS=(
 ["COCKPIT_ADMIN_HASHED_PASSWORD"]="hashedpassword"
 ["PIA_OPENVPN_USERNAME"]="username"
 ["PIA_OPENVPN_PASSWORD"]="password"
 ["PORTAINER_ADMIN_USERNAME"]="username"
 ["PORTAINER_ADMIN_PASSWORD"]="password"
 ["QBITTORRENT_WEBUI_USERNAME"]="username"
 ["QBITTORRENT_WEBUI_PASSWORD"]="password"
)

SECRET_NAMES=(
 PASSWORD_HASH
 IONOS_API_KEY
 PUBLIC_BASE_DOMAIN
 MONGODB_PASSWORD
 MONGO_EXPRESS_PASSWORD
 CLIPROXYAPI_KEY
 BIFROST_ENCRYPTION_KEY
 BIFROST_API_KEY
 OMNIROUTE_OPENCODE_API_KEY
 OMNIROUTE_PI_API_KEY
 EXA_API_KEY
 MITMPROXY_CA_KEY
 MITMPROXY_CA_CERT
 MITMPROXY_WEB_PASSWORD
 OMNIROUTE_INITIAL_PASSWORD
 VPN_PROXY_API_KEY
 SERVICES_AUTH_PASSWORD
 MAIN_VPS_INITRD_SSH_HOST_KEY
 DOKPLOY_AUTH_SECRET
 COCKPIT_ADMIN_HASHED_PASSWORD
 PIA_OPENVPN_USERNAME
 PIA_OPENVPN_PASSWORD
 PORTAINER_ADMIN_USERNAME
 PORTAINER_ADMIN_PASSWORD
 PORTAINER_API_KEY
 QBITTORRENT_WEBUI_USERNAME
 QBITTORRENT_WEBUI_PASSWORD
)

PASS_CREDENTIAL_PARSER="${PASS_CREDENTIAL_PARSER:-${FLAKE_DIR}/packages/pass-credential/pass-credential}"

nix_escape_double_quoted() {
 local value="$1"
 value="${value//$'\n'/}"
 value="${value//\\/\\\\}"
 value="${value//\"/\\\"}"
 value="${value//\$\{/\\\$\{}"
 printf '%s' "$value"
}

nix_escape_indented_string() {
 local value="$1"
 value="${value//\'\'/\'\'\'}"
 value="${value//\$\{/\'\'\$\{}"
 printf '%s' "$value"
}

write_secret_assignment() {
 local env_var="$1"
 local var_value="$2"

 if [[ "$var_value" == *$'\n'* ]]; then
  printf "  %s = ''\n" "$env_var"
  printf '%s' "$(nix_escape_indented_string "$var_value")"
  printf "'';\n"
 else
  printf '  %s = "%s";\n' "$env_var" "$(nix_escape_double_quoted "$var_value")"
 fi
}

load_secret_value() {
 local env_var="$1"
 local pass_path="$2"
 local output_file="$3"
 local secret_field="${SECRET_FIELDS[$env_var]:-}"

 if [ -n "$secret_field" ]; then
  if [ ! -x "$PASS_CREDENTIAL_PARSER" ]; then
   printf 'Credential parser is missing or not executable: %s\n' "$PASS_CREDENTIAL_PARSER" >&2
   return 1
  fi
  pass "$pass_path" | "$PASS_CREDENTIAL_PARSER" "$secret_field" >"$output_file"
 else
  pass "$pass_path" >"$output_file"
 fi
}

# Function to write secrets into secrets.nix. The caller must only invoke this
# after every required secret is present; the generated file is atomically moved
# into place so failed writes never leave a partial secrets.nix.
write_secrets_nix() {
 local secrets_file="${FLAKE_DIR}/secrets.nix"
 local tmp_file="${secrets_file}.tmp.$$"
 log "Writing ${#SECRET_NAMES[@]} secrets to ${secrets_file} as flake.secrets"

 local env_var
 for env_var in "${SECRET_NAMES[@]}"; do
  if [ -z "${!env_var:-}" ]; then
   error "Refusing to write partial secrets.nix; ${env_var} is empty or missing"
   return 1
  fi
 done

 {
  printf '%s\n' "# AUTO-GENERATED by rebuild.sh from password-store — do not edit manually"
  printf '%s\n' "{ flake.secrets = {"
  for env_var in "${SECRET_NAMES[@]}"; do
   write_secret_assignment "$env_var" "${!env_var}"
  done
  printf '%s\n' "}; }"
 } >"$tmp_file"

 if [ -r "$secrets_file" ] && [ "$(<"$secrets_file")" = "$(<"$tmp_file")" ]; then
  rm -f "$tmp_file"
  success "Secrets unchanged at ${secrets_file}"
  return 0
 fi

 mv "$tmp_file" "$secrets_file"
 success "Secrets written to ${secrets_file}"
}

existing_secrets_nix_complete() {
 local secrets_file="${FLAKE_DIR}/secrets.nix"

 [ -s "$secrets_file" ] || return 1

 local env_var
 for env_var in "${SECRET_NAMES[@]}"; do
  if ! grep -Eq "^[[:space:]]*${env_var}[[:space:]]*=" "$secrets_file"; then
   return 1
  fi
 done
}

# Load all secrets from password-store
load_secrets() {
 if [ "$SKIP_SECRETS" = true ]; then
  warn "Skipping password-store secret loading because --skip-secrets was set"
  return 0
 fi

 section "Loading secrets"
 log "Loading ${#SECRET_NAMES[@]} secrets from password-store in parallel"

 if ! command_exists pass; then
  error "password-store (pass) is not installed. Please install it first."
  return 1
 fi

 local loaded_count=0
 local failed_count=0
 local failed_secrets=()
 local secrets_tmp
 secrets_tmp="$(mktemp -d "${TMPDIR:-/tmp}/rebuild-secrets.XXXXXXXX")"
 local -a secret_names=()
 local -a secret_pids=()
 local -a secret_paths=()
 local env_var pass_path

 for env_var in "${SECRET_NAMES[@]}"; do
  pass_path="${SECRETS_MAP[$env_var]}"
  if [ -z "$env_var" ] || [ -z "$pass_path" ]; then
   rm -rf "$secrets_tmp"
   error "Invalid secret configuration: env_var='$env_var', pass_path='$pass_path'"
   return 1
  fi
  local secret_field="${SECRET_FIELDS[$env_var]:-}"
  debug_log "Queueing ${env_var} from ${pass_path}${secret_field:+ field ${secret_field}}"
  load_secret_value "$env_var" "$pass_path" "${secrets_tmp}/${env_var}.value" 2>"${secrets_tmp}/${env_var}.err" &
  secret_names+=("$env_var")
  secret_paths+=("$pass_path")
  secret_pids+=("$!")
 done

 local i pid
 for i in "${!secret_names[@]}"; do
  env_var="${secret_names[$i]}"
  pass_path="${secret_paths[$i]}"
  pid="${secret_pids[$i]}"
  if wait "$pid"; then
   local secret_value
   secret_value="$(<"${secrets_tmp}/${env_var}.value")"
   export "$env_var"="$secret_value"
   loaded_count=$((loaded_count + 1))
   debug_log "Loaded ${env_var} from ${pass_path}"
  else
   failed_count=$((failed_count + 1))
   failed_secrets+=("$env_var ($pass_path)")
   if [ "$DEBUG" = true ] && [ -s "${secrets_tmp}/${env_var}.err" ]; then
    while IFS= read -r line; do
     debug_log "${env_var}: ${line}"
    done <"${secrets_tmp}/${env_var}.err"
   fi
  fi
 done

 rm -rf "$secrets_tmp"

 log "Secrets loading complete: $loaded_count loaded, $failed_count failed"
 if [ "$failed_count" -gt 0 ]; then
  warn "Failed to load the following secrets:"
  for failed in "${failed_secrets[@]}"; do
   warn "  - $failed"
  done

  if existing_secrets_nix_complete; then
   warn "Keeping existing complete secrets.nix; refusing to overwrite it with partial password-store output."
   return 0
  fi
  error "Secret loading failed and no complete secrets.nix exists to keep"
  return 1
 fi

 write_secrets_nix
}

# Git operations (optional)
git_status() {
 if command_exists git && [ -d "${FLAKE_DIR}/.git" ]; then
  log "Checking git status..."
  cd "${FLAKE_DIR}"
  if ! git diff --quiet || ! git diff --cached --quiet; then
   warn "There are uncommitted changes in the flake directory"
   git status --short
  else
   success "Git working directory is clean"
  fi
  cd - >/dev/null
 fi
}

git_commit_backup() {
 if command_exists git && [ -d "${FLAKE_DIR}/.git" ]; then
  log "Creating git backup commit..."
  cd "${FLAKE_DIR}"
  git add .
  git commit -m "Backup before rebuild $(date)" --allow-empty || true
  cd - >/dev/null
 fi
}

# Backup current system (optional)
backup_system() {
 log "Creating system backup..."
 if command_exists nixos-rebuild; then
  run_cmd nixos-rebuild build --flake "${FLAKE_REF}#${HOST}" "${NIX_ARGS[@]}"
  success "System backup created"
 fi
}

# Run one OpenCode LSP request without interleaving its output with other workers.
lint_lsp_worker() {
 local file="$1"
 local result_file="$2"
 local absolute_file output command_status=0 worker_status=0

 absolute_file="$(realpath -e "$file")"
 if output="$(opencode debug lsp diagnostics "$file" 2>&1)"; then
  :
 else
  command_status=$?
 fi

 {
  printf '[lsp] %s\n' "$file"
  if ((command_status != 0)); then
   printf '[FAIL] opencode exited with status %d\n%s\n' "$command_status" "$output"
   worker_status=1
  elif jq -e --arg file "$absolute_file" '
   type == "object"
   and has($file)
   and (.[$file] | type == "array")
  and ([.[$file][] | select((.severity // 1) == 1)] | length == 0)
  ' <<<"$output" >/dev/null 2>&1; then
   printf '[PASS] no error diagnostics\n'
  else
   printf '[FAIL] missing, malformed, or error diagnostics\n%s\n' "$output"
   worker_status=1
  fi
 } >"$result_file"

 return "$worker_status"
}

lint_lsp_diagnostics() {
 local result_dir file result_file pid status=0 count=0
 local -a pids=()

 if ! command_exists opencode || ! command_exists jq; then
  error "LSP diagnostics require opencode and jq"
  return 1
 fi

 result_dir="$(mktemp -d)"
 log "Checking OpenCode LSP diagnostics for tracked Nix and shell sources (up to 8 workers)"

 while IFS= read -r -d '' file; do
  count=$((count + 1))
  printf -v result_file '%s/%06d.log' "$result_dir" "$count"
  lint_lsp_worker "$file" "$result_file" &
  pids+=("$!")

  if ((${#pids[@]} >= 8)); then
   pid="${pids[0]}"
   pids=("${pids[@]:1}")
   if wait "$pid"; then
    :
   else
    status=1
   fi
  fi
 done < <(
  git ls-files -z -- \
   '*.nix' '*.sh' '*.bash' '*.zsh'
 )

 for pid in "${pids[@]}"; do
  if wait "$pid"; then
   :
  else
   status=1
  fi
 done

 if ((count == 0)); then
  warn "No tracked files are covered by the configured OpenCode LSP lane"
 else
  for result_file in "$result_dir"/*.log; do
   cat "$result_file"
  done
 fi
 rm -rf "$result_dir"

 if ((status != 0)); then
  error "OpenCode LSP diagnostics failed"
  return 1
 fi
 success "OpenCode LSP diagnostics passed for ${count} files"
}

lint_nixfmt() {
 if ! command_exists nix; then
  error "Nix formatting checks require nix"
  return 1
 fi

 log "Checking Nix formatting with nixfmt-tree"
 run_cmd nix run nixpkgs#nixfmt-tree -- --ci .
}

lint_typescript() {
 local workspace runner config package file status=0
 local -a package_dirs=() source_files=() loose_files=() all_source_files=() checks=()

 if ! command_exists bun || ! command_exists git || ! command_exists jq || ! command_exists nix; then
  error "TypeScript diagnostics require bun, git, jq, and nix"
  return 1
 fi
 if [ ! -d "${FLAKE_DIR}/node_modules/@types/bun" ] || [ ! -d "${FLAKE_DIR}/node_modules/@types/node" ]; then
  error "TypeScript diagnostics require installed workspace dependencies: bun install --frozen-lockfile"
  return 1
 fi

 mapfile -d '' -t package_dirs < <(
  git ls-files -z -- 'packages/*/package.json' |
   while IFS= read -r -d '' file; do
    printf '%s\0' "$(dirname "$file")"
   done |
   sort -zu
 )
 mapfile -d '' -t all_source_files < <(git ls-files -z -- '*.ts')
 log "Checking ${#all_source_files[@]} tracked TypeScript entrypoints from ${#package_dirs[@]} package manifests"
 workspace="$(mktemp -d)"

 for package in "${package_dirs[@]}"; do
  mapfile -d '' -t source_files < <(
   git ls-files -z -- "${package}/**" |
    while IFS= read -r -d '' file; do
     case "$file" in
     *.ts) printf '%s\0' "$file" ;;
     esac
    done
  )
  ((${#source_files[@]} > 0)) || continue
  config="${workspace}/${package##*/}.json"
  source_files=("${source_files[@]/#${package}/${FLAKE_DIR}/${package}/}")
  if [ -f "${FLAKE_DIR}/${package}/tsconfig.json" ]; then
   jq -n \
    --arg extends "${FLAKE_DIR}/${package}/tsconfig.json" \
    --arg root_types "${FLAKE_DIR}/node_modules/@types" \
    --args '
    {
      extends: $extends,
      compilerOptions: {
        typeRoots: [$root_types],
        types: ["bun", "node"]
      },
      files: $ARGS.positional
    }
   ' "${source_files[@]}" >"$config"
  else
   jq -n \
    --arg root_types "${FLAKE_DIR}/node_modules/@types" \
    --args '
    {
     compilerOptions: {
      allowImportingTsExtensions: true,
      lib: ["ESNext", "DOM"],
      module: "Preserve",
      moduleDetection: "force",
      moduleResolution: "Bundler",
      noEmit: true,
      skipLibCheck: true,
      target: "ESNext",
      typeRoots: [$root_types],
      types: ["bun", "node"]
     },
     files: $ARGS.positional
    }
   ' "${source_files[@]}" >"$config"
  fi
  checks+=("${package#packages/} (${#source_files[@]} files)" "$config")
 done

 for file in "${all_source_files[@]}"; do
  for package in "${package_dirs[@]}"; do
   case "$file" in
   "${package}"/*) continue 2 ;;
   esac
  done
  loose_files+=("${FLAKE_DIR}/${file}")
 done

 if ((${#loose_files[@]} > 0)); then
  config="${workspace}/repository-typescript.json"
  jq -n \
   --arg root_types "${FLAKE_DIR}/node_modules/@types" \
   --args '
   {
    compilerOptions: {
     allowImportingTsExtensions: true,
     lib: ["ESNext", "DOM"],
     module: "Preserve",
     moduleDetection: "force",
     moduleResolution: "Bundler",
     noEmit: true,
     skipLibCheck: true,
     target: "ESNext",
     typeRoots: [$root_types],
     types: ["bun", "node"]
    },
    files: $ARGS.positional
   }
  ' "${loose_files[@]}" >"$config"
  checks+=("repository sources (${#loose_files[@]} files)" "$config")
 fi

 runner="${workspace}/run-typescript-checks"
 cat >"$runner" <<'EOF'
#!/usr/bin/env bash
set -u

status=0
while (($# > 0)); do
 label="$1"
 config="$2"
 shift 2
 printf '\n[typescript] %s\n' "$label"
 if tsc --noEmit --pretty false --project "$config"; then
  printf '[PASS] TypeScript diagnostics clear\n'
 else
  status=1
 fi
done
exit "$status"
EOF
 chmod +x "$runner"

 if ((${#checks[@]} == 0)); then
  rm -rf "$workspace"
  success "No tracked TypeScript files to check"
  return 0
 fi

 if ! nix shell nixpkgs#typescript --command "$runner" "${checks[@]}"; then
  status=1
 fi
 rm -rf "$workspace"

 if ((status != 0)); then
  error "TypeScript diagnostics failed"
  return 1
 fi
 success "TypeScript diagnostics passed"
}

lint_prettier() {
 local -a files=()
 local prettier_bin="${FLAKE_DIR}/node_modules/.bin/prettier"

 if [ ! -x "$prettier_bin" ]; then
  error "Prettier format checks require root dependencies: bun install --frozen-lockfile"
  return 1
 fi

 mapfile -d '' -t files < <(
  git ls-files -z -- \
   '*.css' '*.cts' '*.html' '*.json' '*.json5' '*.jsonc' '*.js' '*.jsx' '*.mdx' '*.mjs' '*.mts' '*.ts' '*.tsx' '*.yaml' '*.yml'
 )
 if ((${#files[@]} == 0)); then
  success "No tracked Prettier-supported files to check"
  return 0
 fi
 log "Checking Prettier formatting for ${#files[@]} tracked files"
 "$prettier_bin" --check --ignore-unknown --cache -- "${files[@]}"
}

lint_markdown() {
 local -a files=()
 local markdownlint_bin="${FLAKE_DIR}/node_modules/.bin/markdownlint-cli2"

 if [ ! -x "$markdownlint_bin" ]; then
  error "Markdown checks require root dependencies: bun install --frozen-lockfile"
  return 1
 fi

 mapfile -d '' -t files < <(git ls-files -z -- README.md 'docs/**/*.md' 'docs/**/*.mdx' 'docs/**/*.markdown')
 if ((${#files[@]} == 0)); then
  success "No tracked Markdown files to check"
  return 0
 fi

 log "Checking Markdown lint rules for ${#files[@]} tracked repository documentation files"
 "$markdownlint_bin" --config "${FLAKE_DIR}/.markdownlint.json" -- "${files[@]}"
}

lint_workspace() {
 local result_dir lane pid status=0
 local -a lanes=(lint_lsp_diagnostics lint_nixfmt lint_typescript lint_prettier lint_markdown)
 local -a pids=()

 section "Linting repository"
 log "Running OpenCode LSP, nixfmt, TypeScript, Prettier, and Markdown checks in parallel"
 result_dir="$(mktemp -d)"

 for lane in "${lanes[@]}"; do
  "$lane" >"${result_dir}/${lane}.log" 2>&1 &
  pids+=("$!")
 done

 for pid in "${pids[@]}"; do
  if wait "$pid"; then
   :
  else
   status=1
  fi
 done

 for lane in "${lanes[@]}"; do
  printf '\n%s\n' "=== ${lane} ==="
  cat "${result_dir}/${lane}.log"
 done
 rm -rf "$result_dir"

 if ((status != 0)); then
  error "Repository lint failed"
  return 1
 fi
 success "Repository lint passed"
}

# Validate flake (optional)
validate_flake() {
 local lint_log="" lint_pid="" status=0

 section "Validating flake"
 if [ "$SKIP_LINT" = true ]; then
  warn "Skipping repository lint because --skip-lint was set"
 else
  lint_log="$(mktemp)"
  lint_workspace >"$lint_log" 2>&1 &
  lint_pid="$!"
 fi

 log "Validating flake configuration..."
 if ! run_cmd nix flake check "${FLAKE_REF}" "${NIX_ARGS[@]}"; then
  status=1
 fi

 if [ -n "$lint_pid" ]; then
  if wait "$lint_pid"; then
   :
  else
   status=1
  fi
  cat "$lint_log"
  rm -f "$lint_log"
 fi

 if ((status != 0)); then
  error "Flake validation failed"
  return 1
 fi
 success "Flake validation passed"
}

# Build system
build_system() {
 section "Building system"
 log "Building system configuration for host: ${HOST}"
 if ! run_cmd nixos-rebuild build --flake "${FLAKE_REF}#${HOST}" "${NIX_ARGS[@]}"; then
  error "System build failed for host: ${HOST}"
  return 1
 fi
 success "System built successfully for host: ${HOST}"
}

# Dry run
dry_run() {
 section "Dry run"
 log "Performing dry run for host: ${HOST}"
 if ! run_cmd nixos-rebuild dry-run --flake "${FLAKE_REF}#${HOST}" "${NIX_ARGS[@]}"; then
  error "Dry run failed for host: ${HOST}"
  return 1
 fi
 success "Dry run completed successfully for host: ${HOST}"
}

# Switch to new system
switch_system() {
 section "Switching system"
 log "Switching to new system configuration for host: ${HOST}"
 if ! run_sudo nixos-rebuild switch --flake "${FLAKE_REF}#${HOST}" "${NIX_ARGS[@]}"; then
  error "System switch failed for host: ${HOST}"
  return 1
 fi
 success "System switched successfully for host: ${HOST}"
}

matrix_fetch_json() {
 # `hostModuleMatrix` only exports metadata for the overview, so read-only eval avoids
 # unnecessary store side effects while keeping the preview fast. Source: `nix eval --help`.
 nix eval --json --read-only "${FLAKE_REF}#hostModuleMatrix" "${NIX_ARGS[@]}"
}

matrix_print_rule() {
 local width="${1:-72}"
 # `tr` is byte-oriented, so replacing spaces with UTF-8 box-drawing glyphs
 # corrupts the rule into mojibake instead of repeating `─` cleanly.
 local i
 for ((i = 0; i < width; i++)); do
  printf '─'
 done
 printf '\n'
}

matrix_print_section() {
 local title="$1"
 printf '\n%b\n' "${MAGENTA}╭─ ${BOLD}${title}${NC}"
 printf '%b\n' "${DIM}$(matrix_print_rule 72)${NC}"
}

matrix_flush_table() {
 local title="$1"
 shift

 if [ "$#" -eq 0 ]; then
  return 0
 fi

 matrix_print_section "$title"
 printf '%s\n' "$@" | column -t -s $'\t'
}

matrix_emit_render_blocks() {
 local matrix_json="$1"
 printf '%s\n' "$matrix_json" | jq -r '
      def section($title): ["SECTION", $title] | @tsv;
      def row($cols): (["ROW"] + $cols) | @tsv;
      def title_for($category):
        if $category == "profiles" then "Profile capability grid"
        elif $category == "features" then "Feature capability grid"
        elif $category == "services" then "Service capability grid"
        elif $category == "programs" then "Program capability grid"
        else ($category + " capability grid")
        end;
      def names_for($entries; $category):
        ($entries | map(.value[$category] // []) | add | unique);
      def grid($entries; $category):
        names_for($entries; $category) as $names
        | if ($names | length) == 0 then
            empty
          else
            section(title_for($category)),
            row(["HOST"] + $names),
            (
              $entries[]
              | . as $entry
              | row(
                  [$entry.key]
                  + (
                    $names
                    | map(. as $name | if (($entry.value[$category] // []) | index($name)) != null then "✓" else "·" end)
                  )
                )
            )
          end;

      to_entries as $entries
      | section("Host capability overview"),
        row(["HOST", "PROFILES", "FEATURES", "SERVICES", "PROGRAMS"]),
        (
          $entries[]
          | row([
              .key,
              ((.value.profiles // []) | length | tostring),
              ((.value.features // []) | length | tostring),
              ((.value.services // []) | length | tostring),
              ((.value.programs // []) | length | tostring)
            ])
        ),
        grid($entries; "profiles"),
        grid($entries; "features"),
        grid($entries; "services"),
        grid($entries; "programs"),
        section("Host module details"),
        row(["HOST", "PROFILES", "FEATURES", "SERVICES", "PROGRAMS"]),
        (
          $entries[]
          | row([
              .key,
              (.value.profiles // [] | if length == 0 then "-" else join(", ") end),
              (.value.features // [] | if length == 0 then "-" else join(", ") end),
              (.value.services // [] | if length == 0 then "-" else join(", ") end),
              (.value.programs // [] | if length == 0 then "-" else join(", ") end)
            ])
        )
    '
}

matrix_render_precomputed_tables() {
 local matrix_json="$1"
 local current_title=""
 local -a current_rows=()
 local line tag payload

 while IFS= read -r line; do
  IFS=$'\t' read -r tag payload <<<"$line"
  case "$tag" in
  SECTION)
   if [ -n "$current_title" ] && [ "${#current_rows[@]}" -gt 0 ]; then
    matrix_flush_table "$current_title" "${current_rows[@]}"
   fi
   current_title="$payload"
   current_rows=()
   ;;
  ROW)
   current_rows+=("${line#$'ROW\t'}")
   ;;
  esac
 done < <(matrix_emit_render_blocks "$matrix_json")

 if [ -n "$current_title" ] && [ "${#current_rows[@]}" -gt 0 ]; then
  matrix_flush_table "$current_title" "${current_rows[@]}"
 fi
}

should_render_module_matrix() {
 local action="$1"
 case "$action" in
 build | switch | dry-run | validate | deploy | install | matrix)
  return 0
  ;;
 *)
  return 1
  ;;
 esac
}

should_load_secrets() {
 local action="$1"
 case "$action" in
 build | switch | dry-run | validate | deploy | install | secrets)
  return 0
  ;;
 *)
  return 1
  ;;
 esac
}

action_requires_host() {
 local action="$1"
 case "$action" in
 lint | matrix | secrets)
  return 1
  ;;
 *)
  return 0
  ;;
 esac
}

action_exists() {
 local action="$1"
 case "$action" in
 switch | build | dry-run | rollback | generations | lint | validate | matrix | secrets | deploy | install)
  return 0
  ;;
 *)
  return 1
  ;;
 esac
}

print_module_matrix() {
 if [ "$SKIP_MATRIX" = true ]; then
  warn "Skipping module matrix preview because --skip-matrix was set"
  return 0
 fi

 if ! command_exists nix || ! command_exists jq; then
  warn "Skipping module matrix preview (requires both nix and jq)"
  return 0
 fi

 local matrix_json
 local matrix_error
 matrix_error="$(mktemp "${TMPDIR:-/tmp}/rebuild-matrix.XXXXXXXX")"
 if ! matrix_json=$(matrix_fetch_json 2>"$matrix_error"); then
  warn "Skipping module matrix preview (hostModuleMatrix export unavailable for ${FLAKE_REF})"
  if [ -s "$matrix_error" ]; then
   warn "Matrix eval error: $(<"$matrix_error")"
  fi
  rm -f "$matrix_error"
  return 0
 fi
 rm -f "$matrix_error"

 section "Module matrix preview"
 log "Module matrix preview"
 matrix_render_precomputed_tables "$matrix_json"
}

# Rollback system
rollback_system() {
 section "Rolling back system"
 log "Rolling back to previous system generation for host: ${HOST}"
 if ! run_sudo nixos-rebuild --rollback switch "${NIX_ARGS[@]:1}"; then
  error "System rollback failed for host: ${HOST}"
  return 1
 fi
 success "System rolled back successfully for host: ${HOST}"
}

# Show generations
show_generations() {
 section "System generations"
 log "Current system generations for host: ${HOST}"
 run_sudo nix-env --list-generations --profile /nix/var/nix/profiles/system
}

# Parse command-line options
parse_options() {
 REMAINING_ARGS=()

 while [[ $# -gt 0 ]]; do
  case $1 in
  --help)
   cat <<EOF
Usage:
  HOST=<host> $0 [OPTIONS] [ACTION] [TARGET]

Default action is 'switch'. All build/eval actions use ${FLAKE_REF}#<host>,
so generated files such as secrets.nix are included even when invoking the
script from another directory.

Environment Variables:
  HOST       Target nixosConfigurations attribute. Required except lint/matrix/secrets.
  ARGS       Extra nix/nixos-rebuild flags appended after --impure.
             Defaults to: " --accept-flake-config"

Arguments:
  ACTION     One of the actions below. Defaults to switch.
  TARGET     SSH target for deploy/install only, e.g. root@192.168.1.100.

Actions:
  switch       Write secrets.nix, build, and activate the selected host.
  build        Write secrets.nix and build without activating.
  dry-run      Ask nixos-rebuild to print the activation delta without changing state.
  lint         Run parallel LSP, Nix, TypeScript, Prettier, and Markdown checks.
  validate     Evaluate host matrix, run nix flake check, and lint in parallel.
  matrix       Evaluate and render hostModuleMatrix only; skips secrets by default.
  secrets      Fetch all pass entries in parallel and atomically rewrite secrets.nix only.
  deploy       Switch a remote machine through nixos-rebuild --target-host TARGET.
  install      Install a remote machine through nixos-anywhere TARGET.
  rollback     Run nixos-rebuild --rollback switch for the local machine.
  generations  Print the full /nix/var/nix/profiles/system generation list.

Options:
  --log-file       Also write color-stripped output to ${SCRIPT_DIR}/rebuild.log.
  --git-backup     Show dirty git state and create a backup commit before mutating actions.
  --validate       Run nix flake check and lint before build/switch/deploy/install/dry-run.
  --backup         Build the current host before switch.
  --no-notify      Disable notify-send desktop notifications.
  --debug          Print queued secret names, matrix eval errors, and command context.
  --trace          Enable shell xtrace after option parsing for command debugging.
  --skip-secrets   Do not call pass or rewrite secrets.nix; useful for pure eval/debug loops.
  --skip-matrix    Do not evaluate/render hostModuleMatrix.
  --skip-lint      Do not run lint as part of validate or --validate.
  --help           Show this help message.

Always-on diagnostics:
  Each section header includes wall-clock timestamp, total runtime, and time since
  the previous section. Final cleanup prints overall runtime even on failure.

Examples:
  HOST=legion5i $0 build
  HOST=legion5i $0 --debug --skip-secrets validate
  $0 lint
  HOST=legion5i $0 --skip-lint validate
  HOST=legion5i $0 --debug matrix
  HOST=legion5i $0 secrets
  HOST=legion5i ARGS="--fallback --accept-flake-config" $0 dry-run
  HOST=main_vps $0 deploy root@192.168.1.100
  HOST=macbook $0 install root@192.168.1.100
EOF
   CLEANUP_QUIET=true
   exit 0
   ;;
  --log-file)
   LOG_FILE="${SCRIPT_DIR}/rebuild.log"
   shift
   ;;
  --git-backup)
   GIT_BACKUP=true
   shift
   ;;
  --validate)
   VALIDATE=true
   shift
   ;;
  --backup)
   BACKUP=true
   shift
   ;;
  --no-notify)
   NOTIFY=false
   shift
   ;;
  --debug)
   DEBUG=true
   shift
   ;;
  --trace)
   TRACE=true
   DEBUG=true
   shift
   ;;
  --skip-secrets)
   SKIP_SECRETS=true
   shift
   ;;
  --skip-matrix)
   SKIP_MATRIX=true
   shift
   ;;
  --skip-lint)
   SKIP_LINT=true
   shift
   ;;
  --)
   shift
   REMAINING_ARGS+=("$@")
   return 0
   ;;
  -*)
   echo "Unknown option: $1" >&2
   echo "Use --help for usage information" >&2
   exit 1
   ;;
  *)
   REMAINING_ARGS+=("$1")
   shift
   ;;
  esac
 done
}

# Deploy to remote host
deploy_system() {
 local target_host="$1"
 if [ -z "$target_host" ]; then
  error "deploy action requires TARGET_HOST argument"
  echo "Usage: $0 <host> deploy <target_host>"
  exit 1
 fi

 section "Deploying system"
 log "Deploying system configuration for host '${HOST}' to remote target: ${target_host}"

 # Deploy on target host using the target host to build packages, etc, using sudo (on normal user rather than root)
 # Use --build-host '${target_host}' to also build on target
 if ! run_cmd nixos-rebuild switch --target-host "${target_host}" --ask-sudo-password --use-substitutes --flake "${FLAKE_REF}#${HOST}" "${NIX_ARGS[@]}"; then
  error "System deployment failed for host '${HOST}' to target: ${target_host}"
  return 1
 fi
 success "System deployed successfully for host '${HOST}' to target: ${target_host}"
}

# Install on remote host using nixos-anywhere
install_system() {
 local target_host="$1"
 if [ -z "$target_host" ]; then
  error "install action requires TARGET_HOST argument"
  echo "Usage: $0 <host> install <target_host>"
  exit 1
 fi

 section "Installing system"
 log "Installing system configuration using nixos-anywhere for host '${HOST}' to remote target: ${target_host}"

 # Install on target host using the using nixos-anywhere
 if ! run_cmd nix run "${NIX_ARGS[@]:1}" github:nix-community/nixos-anywhere -- --impure --flake "${FLAKE_REF}#${HOST}" --target-host "${target_host}"; then
  error "System installment using nixos-anywhere failed for host '${HOST}' to target: ${target_host}"
  return 1
 fi
 success "System installed using nixos-anywhere successfully for host '${HOST}' to target: ${target_host}"
}

# Main function
main() {
 SCRIPT_START_MS="$(now_ms)"
 LAST_SECTION_MS="$SCRIPT_START_MS"
 parse_options "$@"
 if [ "$TRACE" = true ]; then
  set -x
 fi
 refresh_nix_args

 # Extract action and deploy target from remaining arguments
 local action=""
 local deploy_target=""

 # Parse remaining arguments: [action] [args]
 set -- "${REMAINING_ARGS[@]}"
 while [[ $# -gt 0 ]]; do
  if [ -z "$action" ]; then
   action="$1"
  elif [ -z "$deploy_target" ]; then
   deploy_target="$1"
  else
   error "Unexpected extra argument: $1"
   echo "Usage: HOST=<host> $0 [OPTIONS] [ACTION] [ARGS]"
   echo "Use --help for more information"
   exit 1
  fi
  shift
 done

 action="${action:-switch}"

 if ! action_exists "$action"; then
  error "Unknown action: ${action}"
  echo "Usage: HOST=<host> $0 [OPTIONS] {switch|build|dry-run|rollback|generations|lint|validate|matrix|secrets|deploy|install}"
  echo "Use --help for more information"
  exit 1
 fi

 if [ "$action" = "matrix" ]; then
  SKIP_SECRETS=true
 fi

 # Validate required HOST environment variable
 if [ -z "$HOST" ] && action_requires_host "$action"; then
  error "HOST environment variable is required"
  echo "Usage: HOST=<host> $0 [OPTIONS] [ACTION] [ARGS]"
  echo "Use --help for more information"
  exit 1
 fi

 case "${action}" in
 deploy | install) ;;
 *)
  if [ -n "$deploy_target" ]; then
   error "Action '${action}' does not accept an extra argument: ${deploy_target}"
   echo "Usage: HOST=<host> $0 [OPTIONS] [ACTION]"
   echo "Use --help for more information"
   exit 1
  fi
  ;;
 esac

 send_notification "info" "NixOS Rebuild" "Starting ${action} for ${HOST}..."

 section "Starting ${action}"
 log "Starting NixOS rebuild script"
 log "Host: ${HOST:-<not required>}"
 log "Flake directory: ${FLAKE_DIR}"
 log "Flake reference: ${FLAKE_REF}"
 log "Action: ${action}"
 if [ -n "$ARGS" ]; then
  log "Additional nix args: ${ARGS}"
 fi
 debug_log "NIX_SSHOPTS=${NIX_SSHOPTS}"
 debug_log "skip_secrets=${SKIP_SECRETS} skip_matrix=${SKIP_MATRIX} skip_lint=${SKIP_LINT} validate=${VALIDATE} backup=${BACKUP} git_backup=${GIT_BACKUP}"

 cd "${FLAKE_DIR}"

 # Load secrets (core functionality)
 if should_load_secrets "$action"; then
  load_secrets
 fi

 if should_render_module_matrix "$action"; then
  print_module_matrix
 fi

 # Optional git status check
 if [ "$GIT_BACKUP" = true ]; then
  git_status
 fi

 case "${action}" in
 "build")
  if [ "$VALIDATE" = true ]; then
   validate_flake
  fi
  build_system
  ;;
 "switch")
  if [ "$GIT_BACKUP" = true ]; then
   git_commit_backup
  fi
  if [ "$BACKUP" = true ]; then
   backup_system
  fi
  if [ "$VALIDATE" = true ]; then
   validate_flake
  fi
  switch_system
  ;;
 "dry-run")
  if [ "$VALIDATE" = true ]; then
   validate_flake
  fi
  dry_run
  ;;
 "rollback")
  rollback_system
  ;;
 "generations")
  show_generations
  ;;
 "lint")
  lint_workspace
  ;;
 "validate")
  validate_flake
  ;;
 "matrix")
  ;;
 "secrets")
  ;;
 "deploy")
  if [ "$GIT_BACKUP" = true ]; then
   git_commit_backup
  fi
  if [ "$VALIDATE" = true ]; then
   validate_flake
  fi
  deploy_system "$deploy_target"
  ;;
 "install")
  if [ "$GIT_BACKUP" = true ]; then
   git_commit_backup
  fi
  if [ "$VALIDATE" = true ]; then
   validate_flake
  fi
  install_system "$deploy_target"
  ;;
 *)
  error "Unknown action: ${action}"
  echo "Usage: HOST=<host> $0 [OPTIONS] {switch|build|dry-run|rollback|generations|lint|validate|matrix|secrets|deploy|install}"
  echo "Use --help for more information"
  exit 1
  ;;
 esac

 success "Rebuild script completed successfully"
 send_notification "success" "NixOS Rebuild" "${action^} completed successfully for ${HOST}"
}

# Cleanup on exit
cleanup() {
 local exit_code=$?
 if [ "$CLEANUP_QUIET" = true ]; then
  return
 fi
 local finish_ms total_ms
 finish_ms="$(now_ms)"
 if ((SCRIPT_START_MS > 0)); then
  total_ms=$((finish_ms - SCRIPT_START_MS))
 else
  total_ms=0
 fi
 if [ ${exit_code} -ne 0 ]; then
  if [ "$NOTIFIED_ERROR" = false ]; then
   send_notification "error" "NixOS Rebuild Failed" "Script exited with code ${exit_code}"
  fi
  log "Script failed with exit code ${exit_code}"
 fi
 log "Script finished in $(format_duration_ms "$total_ms")"
}

trap cleanup EXIT

# Run main function with all arguments
main "$@"
