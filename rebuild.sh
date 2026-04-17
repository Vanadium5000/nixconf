#!/usr/bin/env bash
set -euo pipefail
shopt -s expand_aliases

# Simplified NixOS Rebuild Script
# Core features: Secret loading, colored logging, basic rebuild actions
# Optional features: Controlled by command-line flags

# Use custom QuickShell menu for askpass
QS_CMD='/run/current-system/sw/bin/qs-askpass'
if command -v "$QS_CMD" &> /dev/null; then
    export SUDO_ASKPASS="$QS_CMD"
    alias sudo='sudo -A'
fi

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLAKE_DIR="${SCRIPT_DIR}"
FLAKE_REF="path:."
HOST="${HOST:-}"
ARGS="${ARGS:-} --accept-flake-config"
# Keep interactive SSH responsive, but do not force these settings onto bulk rsync.
export NIX_SSHOPTS="${NIX_SSHOPTS:- -4 -o ControlMaster=auto -o ControlPersist=600 -o ControlPath=~/.ssh/opencode-rebuild-%C -o Compression=no -o IPQoS=throughput}"
# Dedicated rsync transport opts: disable multiplexing and auth fallbacks so one
# large file gets a clean throughput-oriented SSH session.
export RSYNC_SSHOPTS="${RSYNC_SSHOPTS:- -4 -o ControlMaster=no -o ControlPath=none -o Compression=no -o IPQoS=throughput -o PreferredAuthentications=publickey -T -x -c aes128-gcm@openssh.com}"
# Parallel deploy transfers intentionally reuse the throughput-oriented SSH
# profile because this link only reaches expected throughput when several
# independent streams are active at the same time.
export DEPLOY_PATH_SSHOPTS="${DEPLOY_PATH_SSHOPTS:-${RSYNC_SSHOPTS}}"
export DEPLOY_TRANSFER_MODE="${DEPLOY_TRANSFER_MODE:-parallel-paths}"
export DEPLOY_JOBS="${DEPLOY_JOBS:-6}"
export DEPLOY_RETRIES="${DEPLOY_RETRIES:-2}"


# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default options (all optional features off)
LOG_FILE=""
GIT_BACKUP=false
VALIDATE=false
BACKUP=false
NOTIFY=true
NOTIFIED_ERROR=false

# Logging functions
log() {
    local msg="$*"
    if [ -n "$LOG_FILE" ]; then
        echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $msg" | tee -a "$LOG_FILE"
    else
        echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $msg"
    fi
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
    echo -e "${RED}[ERROR]${NC} $*" >&2
    if [ -n "$LOG_FILE" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >> "$LOG_FILE"
    fi
    send_notification "error" "NixOS Rebuild Error" "$*"
    NOTIFIED_ERROR=true
}

success() {
    local msg="$*"
    if [ -n "$LOG_FILE" ]; then
        echo -e "${GREEN}[SUCCESS]${NC} $msg" | tee -a "$LOG_FILE"
    else
        echo -e "${GREEN}[SUCCESS]${NC} $msg"
    fi
}

warn() {
    local msg="$*"
    if [ -n "$LOG_FILE" ]; then
        echo -e "${YELLOW}[WARNING]${NC} $msg" | tee -a "$LOG_FILE"
    else
        echo -e "${YELLOW}[WARNING]${NC} $msg"
    fi
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Secrets configuration - easily extensible associative array
# Format: ["env_var_name"]="password_store_path"
declare -A SECRETS_MAP=(
    ["PASSWORD_HASH"]="system/matrix/hashedPassword"
    ["MY_WEBSITE_ENV"]="my_website/env_file"
    ["MONGODB_PASSWORD"]="system/mongodb_password"
    ["MONGO_EXPRESS_PASSWORD"]="system/mongo_express_password"
    ["ANTIGRAVITY_MANAGER_KEY"]="system/antigravity-manager-key"
    ["CLIPROXYAPI_KEY"]="system/cliproxyapi-key"
    ["EXA_API_KEY"]="system/exa-api-key"
    ["OPENCODE_SERVER_PASSWORD"]="system/opencode-server-password"
    ["MITMPROXY_CA_KEY"]="system/mitmproxy-ca-key"
    ["MITMPROXY_CA_CERT"]="system/mitmproxy-ca-cert"
    ["VPN_PROXY_API_KEY"]="system/vpn-proxy-api-key"
    ["SERVICES_AUTH_PASSWORD"]="system/services-auth-password"
)

# Load a single secret from password-store
load_secret() {
    local env_var="$1"
    local pass_path="$2"

    if [ -z "$env_var" ] || [ -z "$pass_path" ]; then
        error "Invalid secret configuration: env_var='$env_var', pass_path='$pass_path'"
        return 1
    fi

    local secret_value
    if secret_value=$(pass "$pass_path"); then
        export "$env_var"="$secret_value"
        success "Loaded $env_var from password-store"
        return 0
    else
        warn "Could not load $env_var from password-store path: $pass_path. Using environment variable if set."
        return 1
    fi
}

# Function to write secrets into secrets.nix
write_secrets_nix() {
    local secrets_file="${FLAKE_DIR}/secrets.nix"
    log "Writing secrets to ${secrets_file} as a Nix object (flake.secrets)"

    {
        echo "# AUTO-GENERATED by rebuild.sh from password-store — do not edit manually"
        echo "{ flake.secrets = {"
        for env_var in "${!SECRETS_MAP[@]}"; do
            local var_name="$env_var"
            local var_value="${!var_name:-}"
            if [ -n "$var_value" ]; then
                # Check if string contains newlines (multiline like PEM certs)
                if printf '%s' "$var_value" | grep -q $'\n'; then
                    # Multiline string: use Nix '' syntax and escape existing ''
                    escaped_value=$(printf '%s' "$var_value" | sed "s/''/'''/g")
                    echo "  ${var_name} = ''"
                    echo "${escaped_value}'';"
                else
                    # Single line string (passwords, hashes): use standard "" syntax and strip trailing newline
                    var_value=$(printf '%s' "$var_value" | tr -d '\n')
                    escaped_value=$(printf '%s' "$var_value" | sed 's/\\/\\\\/g; s/"/\\"/g')
                    echo "  ${var_name} = \"${escaped_value}\";"
                fi
            fi
        done
        echo "}; }"
    } > "$secrets_file"

    success "Secrets written to ${secrets_file}"
}

# Load all secrets from password-store
load_secrets() {
    log "Loading secrets from password-store..."
    log "Attempting to load ${#SECRETS_MAP[@]} secrets"

    if ! command_exists pass; then
        error "password-store (pass) is not installed. Please install it first."
        return 1
    fi

    local loaded_count=0
    local failed_count=0
    local failed_secrets=()

    for env_var in "${!SECRETS_MAP[@]}"; do
        local pass_path="${SECRETS_MAP[$env_var]}"
        log "Loading secret for $env_var from $pass_path"
        if load_secret "$env_var" "$pass_path"; then
            loaded_count=$((loaded_count + 1))
        else
            failed_count=$((failed_count + 1))
            failed_secrets+=("$env_var ($pass_path)")
        fi
    done

    log "Secrets loading complete: $loaded_count loaded, $failed_count failed"
    if [ "$failed_count" -gt 0 ]; then
        warn "Failed to load the following secrets:"
        for failed in "${failed_secrets[@]}"; do
            warn "  - $failed"
        done
    fi

    write_secrets_nix

    return $((failed_count > 0 ? 1 : 0))
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
        nixos-rebuild build --flake "path:${FLAKE_DIR}#${HOST}" --impure $ARGS
        success "System backup created"
    fi
}

# Validate flake (optional)
validate_flake() {
    log "Validating flake configuration..."
    if ! nix flake check "${FLAKE_REF}" --impure $ARGS; then
        error "Flake validation failed"
        return 1
    fi
    success "Flake validation passed"
}

# Build system
build_system() {
    log "Building system configuration for host: ${HOST}"
    local cmd="nixos-rebuild build --flake '${FLAKE_REF}#${HOST}' --impure $ARGS"
    log_command "$cmd"
    if ! eval "$cmd"; then
        error "System build failed for host: ${HOST}"
        return 1
    fi
    success "System built successfully for host: ${HOST}"
}

# Dry run
dry_run() {
    log "Performing dry run for host: ${HOST}"
    local cmd="nixos-rebuild dry-run --flake '${FLAKE_REF}#${HOST}' --impure $ARGS"
    log_command "$cmd"
    if ! eval "$cmd"; then
        error "Dry run failed for host: ${HOST}"
        return 1
    fi
    success "Dry run completed successfully for host: ${HOST}"
}

# Build environment variables string from loaded secrets
build_env_vars() {
    local env_vars=""
    for env_var in "${!SECRETS_MAP[@]}"; do
        local var_name="$env_var"
        local var_value="${!var_name:-}"
        if [ -n "$var_value" ]; then
            env_vars="${env_vars}${var_name}='${var_value}' "
        fi
    done
    echo "$env_vars"
}

# Switch to new system
switch_system() {
    log "Switching to new system configuration for host: ${HOST}"
    write_secrets_nix

    local cmd="sudo nixos-rebuild switch --flake '${FLAKE_REF}#${HOST}' --impure $ARGS"
    log_command "$cmd"
    if ! eval "$cmd"; then
        error "System switch failed for host: ${HOST}"
        return 1
    fi
    success "System switched successfully for host: ${HOST}"
}

matrix_fetch_json() {
    local -a nix_args=(--impure)
    if [ -n "$ARGS" ]; then
        read -r -a extra_args <<< "$ARGS"
        nix_args+=("${extra_args[@]}")
    fi

    nix eval --json "${FLAKE_REF}#hostModuleMatrix" "${nix_args[@]}" 2>/dev/null
}

matrix_render_summary_table() {
    local matrix_json="$1"
    printf '%s\n' "$matrix_json" | jq -r '
      to_entries[] |
      [
        .key,
        ((.value.profiles // []) | length),
        ((.value.features // []) | length),
        ((.value.services // []) | length),
        ((.value.programs // []) | length)
      ] | @tsv
    ' | {
        printf '%b\n' "${BLUE}HOST\tPROFILES\tFEATURES\tSERVICES\tPROGRAMS${NC}"
        cat
    } | column -t -s $'\t'
}

matrix_render_category_grid() {
    local matrix_json="$1"
    local category="$2"
    local title="$3"

    local -a names
    mapfile -t names < <(
        printf '%s\n' "$matrix_json" | jq -r --arg category "$category" '
          to_entries
          | map(.value[$category] // [])
          | add
          | unique
          | .[]
        '
    )

    if [ "${#names[@]}" -eq 0 ]; then
        return 0
    fi

    local -a hosts
    mapfile -t hosts < <(printf '%s\n' "$matrix_json" | jq -r 'keys[]')

    printf '%b\n' "${BLUE}${title}${NC}"
    {
        printf 'HOST\t'
        printf '%s\t' "${names[@]}"
        printf '\n'

        local host
        local name
        local marker
        for host in "${hosts[@]}"; do
            printf '%s\t' "$host"
            for name in "${names[@]}"; do
                marker=$(printf '%s\n' "$matrix_json" | jq -r --arg host "$host" --arg category "$category" --arg name "$name" '
                  if ((.[ $host ][ $category ] // []) | index($name)) != null then "✓" else "·" end
                ')
                printf '%s\t' "$marker"
            done
            printf '\n'
        done
    } | column -t -s $'\t'
}

matrix_render_host_details() {
    local matrix_json="$1"
    printf '%s\n' "$matrix_json" | jq -r '
      to_entries[]
      | .key as $host
      | [
          $host,
          (.value.profiles // [] | if length == 0 then "-" else join(", ") end),
          (.value.features // [] | if length == 0 then "-" else join(", ") end),
          (.value.services // [] | if length == 0 then "-" else join(", ") end),
          (.value.programs // [] | if length == 0 then "-" else join(", ") end)
        ] | @tsv
    ' | {
        printf '%b\n' "${BLUE}HOST\tPROFILES\tFEATURES\tSERVICES\tPROGRAMS${NC}"
        cat
    } | column -t -s $'\t'
}

print_module_matrix() {
    if ! command_exists nix || ! command_exists jq; then
        warn "Skipping module matrix preview (requires both nix and jq)"
        return 0
    fi

    local matrix_json
    if ! matrix_json=$(matrix_fetch_json); then
        warn "Skipping module matrix preview (hostModuleMatrix export unavailable)"
        return 0
    fi

    log "Module matrix preview"
    matrix_render_summary_table "$matrix_json"
    matrix_render_category_grid "$matrix_json" "profiles" "Profile capability grid"
    matrix_render_category_grid "$matrix_json" "features" "Feature capability grid"
    matrix_render_category_grid "$matrix_json" "services" "Service capability grid"
    matrix_render_category_grid "$matrix_json" "programs" "Program capability grid"
    matrix_render_host_details "$matrix_json"
}

# Rollback system
rollback_system() {
    log "Rolling back to previous system generation for host: ${HOST}"
    local cmd="sudo nixos-rebuild --rollback switch $ARGS"
    log_command "$cmd"
    if ! eval "$cmd"; then
        error "System rollback failed for host: ${HOST}"
        return 1
    fi
    success "System rolled back successfully for host: ${HOST}"
}

# Show generations
show_generations() {
    log "Current system generations for host: ${HOST}"
    local cmd="sudo nix-env --list-generations --profile /nix/var/nix/profiles/system | tail -10"
    log_command "$cmd"
    eval "$cmd"
}

# Parse command-line options
parse_options() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help)
                cat << EOF
Usage: HOST=<host> ARGS="..." $0 [OPTIONS] [ACTION]

Environment Variables:
  HOST        Target host configuration (required)
  ARGS        Additional arguments for all nix commands (e.g., "--fallback --etc")

Arguments:
  ACTION      Action to perform (default: switch)

Actions:
  switch       Switch to new system configuration (default)
  build        Build system configuration without switching
  dry-run      Perform dry run
  rollback     Rollback to previous generation
  generations  Show system generations
  validate     Validate flake configuration
  deploy       Deploy to remote host (requires TARGET_HOST argument)
  install      Install to remote host using nixos-anywhere (requires TARGET_HOST argument)

Options:
  --log-file    Enable logging to file
  --git-backup  Enable automatic git backup commits
  --validate    Enable flake validation
  --backup      Enable system backup before switch
  --no-notify   Disable desktop notifications
  --help        Show this help message

Examples:
  HOST=macbook $0 switch                     # Switch local macbook system
  HOST=macbook $0 build                      # Build macbook configuration
  HOST=macbook $0 deploy root@192.168.1.100  # Deploy to remote host
  HOST=macbook $0 install root@192.168.1.100 # Install to remote host using nixos-anywhere
  HOST=legion5i $0 --validate switch         # Validate before switching legion5i
EOF
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
            -*)
                echo "Unknown option: $1" >&2
                echo "Use --help for usage information" >&2
                exit 1
                ;;
            *)
                break
                ;;
        esac
    done
    # Return remaining arguments as a single string
    echo "$@"
}

# Deploy to remote host
# Build locally, bulk-stream the closure to the target, then activate it remotely.
# This avoids nix copy's slow path-by-path SSH store protocol for large closures.
deploy_system() {
    local target_host="$1"
    if [ -z "$target_host" ]; then
        error "deploy action requires TARGET_HOST argument"
        echo "Usage: $0 <host> deploy <target_host>"
        exit 1
    fi

    local target_user=""
    local target_addr=""
    local resolved_target=""
    if [[ "${target_host}" == *"@"* ]]; then
        target_user="${target_host%@*}"
        target_addr="${target_host#*@}"
    else
        target_addr="${target_host}"
    fi

    # Resolve hostnames once up front so deploy uses one concrete IPv4 route.
    # This avoids SSH flipping between slow/incorrect address families or interfaces.
    if [[ "${target_addr}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        resolved_target="${target_addr}"
    else
        resolved_target=$(getent ahostsv4 "${target_addr}" | awk 'NR == 1 { print $1 }')
        if [ -z "${resolved_target}" ]; then
            error "Could not resolve IPv4 address for target: ${target_addr}"
            exit 1
        fi
    fi

    if [ -n "${target_user}" ]; then
        resolved_target="${target_user}@${resolved_target}"
    fi

    deploy_transfer_single_export() {
        local system_path="$1"
        local resolved_target="$2"
        local requisites_file
        local export_file
        local remote_export_file
        local -a requisites

        requisites_file=$(mktemp)
        export_file=$(mktemp --suffix=.nix-closure)
        remote_export_file="/tmp/${HOST}-system.closure"

        if ! nix-store --query --requisites "${system_path}" > "${requisites_file}"; then
            rm -f "${requisites_file}" "${export_file}"
            error "Failed to query system closure requisites for host '${HOST}'"
            return 1
        fi
        mapfile -t requisites < "${requisites_file}"
        rm -f "${requisites_file}"

        if [ "${#requisites[@]}" -eq 0 ]; then
            rm -f "${export_file}"
            error "System closure requisites list was empty for host '${HOST}'"
            return 1
        fi

        log_command "export nix-store closure to local file"
        if ! nix-store --export "${requisites[@]}" > "${export_file}"; then
            rm -f "${export_file}"
            error "System closure export failed for host '${HOST}'"
            return 1
        fi
        success "System closure exported successfully for host: ${HOST}"

        log_command "copy closure file to ${resolved_target}"
        if ! rsync --whole-file --progress --trust-sender -e "ssh ${RSYNC_SSHOPTS}" "${export_file}" "${resolved_target}:${remote_export_file}"; then
            rm -f "${export_file}"
            error "System closure file copy failed for host '${HOST}' to target: ${resolved_target}"
            return 1
        fi
        success "System closure file copied successfully for host: ${HOST} to target: ${resolved_target}"

        log_command "import closure file on ${resolved_target}"
        if ! ssh -4 "${resolved_target}" "nix-store --import < '${remote_export_file}' && rm -f '${remote_export_file}'"; then
            rm -f "${export_file}"
            error "System closure import failed for host '${HOST}' on target: ${resolved_target}"
            return 1
        fi
        rm -f "${export_file}"
        success "System closure imported successfully for host: ${HOST} on target: ${resolved_target}"
        return 0
    }

    deploy_transfer_parallel_paths() {
        local system_path="$1"
        local resolved_target="$2"
        local requisites_file
        local missing_file
        local remote_stage_dir
        local remote_missing_file
        local path
        local worker_failures

        requisites_file=$(mktemp)
        missing_file=$(mktemp)

        if ! nix-store --query --requisites "${system_path}" > "${requisites_file}"; then
            rm -f "${requisites_file}" "${missing_file}"
            error "Failed to query system closure requisites for host '${HOST}'"
            return 1
        fi

        if ! remote_stage_dir=$(ssh -4 ${DEPLOY_PATH_SSHOPTS} "${resolved_target}" 'mktemp -d /tmp/opencode-closure.XXXXXX'); then
            rm -f "${requisites_file}" "${missing_file}"
            error "Failed to create remote staging directory on target: ${resolved_target}"
            return 1
        fi
        remote_missing_file="${remote_stage_dir}/missing-paths.txt"

        log "Collecting missing store paths on ${resolved_target}"
        if ! ssh -4 ${DEPLOY_PATH_SSHOPTS} "${resolved_target}" 'while IFS= read -r path; do [ -e "$path" ] || printf "%s\n" "$path"; done' < "${requisites_file}" > "${missing_file}"; then
            rm -f "${requisites_file}" "${missing_file}"
            error "Failed to probe remote store paths on target: ${resolved_target}"
            return 1
        fi

        if ! grep -q . "${missing_file}"; then
            rm -f "${requisites_file}" "${missing_file}"
            if ! ssh -4 ${DEPLOY_PATH_SSHOPTS} "${resolved_target}" "rm -rf '${remote_stage_dir}'"; then
                warn "Failed to remove empty remote staging directory: ${remote_stage_dir}"
            fi
            success "All closure paths already exist on target: ${resolved_target}"
            return 0
        fi

        if ! ssh -4 ${DEPLOY_PATH_SSHOPTS} "${resolved_target}" "cat > '${remote_missing_file}'" < "${missing_file}"; then
            rm -f "${requisites_file}" "${missing_file}"
            error "Failed to upload missing store path manifest to target: ${resolved_target}"
            return 1
        fi

        transfer_store_path_to_stage() {
            local store_path="$1"
            local resolved_target="$2"
            local remote_stage_dir="$3"
            local retries="$4"
            local base_name
            local remote_file
            local attempt

            base_name=$(basename "${store_path}")
            remote_file="${remote_stage_dir}/${base_name}.nar"
            attempt=1

            while [ "${attempt}" -le "${retries}" ]; do
                if nix-store --export "${store_path}" | ssh -4 ${DEPLOY_PATH_SSHOPTS} "${resolved_target}" "cat > '${remote_file}'"; then
                    return 0
                fi
                attempt=$((attempt + 1))
                sleep 1
            done

            return 1
        }

        log "Transferring missing closure paths to ${resolved_target} with ${DEPLOY_JOBS} workers"
        worker_failures=0
        while IFS= read -r path; do
            [ -n "${path}" ] || continue
            transfer_store_path_to_stage "${path}" "${resolved_target}" "${remote_stage_dir}" "$((DEPLOY_RETRIES + 1))" &
            while [ "$(jobs -pr | wc -l | tr -d ' ')" -ge "${DEPLOY_JOBS}" ]; do
                if ! wait -n; then
                    worker_failures=1
                fi
            done
        done < "${missing_file}"

        while [ "$(jobs -pr | wc -l | tr -d ' ')" -gt 0 ]; do
            if ! wait -n; then
                worker_failures=1
            fi
        done

        if [ "${worker_failures}" -ne 0 ]; then
            rm -f "${requisites_file}" "${missing_file}"
            error "Parallel closure path transfer failed for host '${HOST}' to target: ${resolved_target}"
            return 1
        fi

        log_command "import staged closure paths on ${resolved_target}"
        if ! ssh -4 ${DEPLOY_PATH_SSHOPTS} "${resolved_target}" "stage_dir='${remote_stage_dir}'; missing_file='${remote_missing_file}'; while IFS= read -r path; do [ -n "$path" ] || continue; base_name=\$(basename "$path"); nix-store --import < "$stage_dir/\${base_name}.nar" || exit 1; done < "$missing_file"; rm -rf "$stage_dir""; then
            rm -f "${requisites_file}" "${missing_file}"
            error "Staged closure import failed for host '${HOST}' on target: ${resolved_target}"
            return 1
        fi

        if ! ssh -4 ${DEPLOY_PATH_SSHOPTS} "${resolved_target}" 'while IFS= read -r path; do [ -e "$path" ] || exit 1; done' < "${requisites_file}"; then
            rm -f "${requisites_file}" "${missing_file}"
            error "Remote closure verification failed for host '${HOST}' on target: ${resolved_target}"
            return 1
        fi

        rm -f "${requisites_file}" "${missing_file}"
        success "System closure transferred and verified successfully for host: ${HOST} on target: ${resolved_target}"
        return 0
    }

    log "Deploying system configuration for host '${HOST}' to remote target: ${target_host} (resolved: ${resolved_target})"
    write_secrets_nix

    local system_path
    log_command "nix build system closure"
    if ! system_path=$(nix --extra-experimental-features 'nix-command flakes' build --print-out-paths "${FLAKE_REF}#nixosConfigurations.${HOST}.config.system.build.toplevel" --no-link --accept-flake-config --impure); then
        error "System build failed for host '${HOST}'"
        return 1
    fi
    success "System built successfully for host: ${HOST}"

    case "${DEPLOY_TRANSFER_MODE}" in
        parallel-paths)
            if ! deploy_transfer_parallel_paths "${system_path}" "${resolved_target}"; then
                return 1
            fi
            ;;
        single-export)
            if ! deploy_transfer_single_export "${system_path}" "${resolved_target}"; then
                return 1
            fi
            ;;
        *)
            error "Unknown DEPLOY_TRANSFER_MODE: ${DEPLOY_TRANSFER_MODE}"
            return 1
            ;;
    esac

    log_command "ssh activate system closure on ${resolved_target}"
    if ! ssh -4 "${resolved_target}" sudo "${system_path}/bin/switch-to-configuration" switch; then
        error "Remote activation failed for host '${HOST}' on target: ${resolved_target}"
        return 1
    fi
    success "System deployed successfully for host '${HOST}' to target: ${resolved_target}"
}
# Install on remote host using nixos-anywhere
install_system() {
    local target_host="$1"
    if [ -z "$target_host" ]; then
        error "install action requires TARGET_HOST argument"
        echo "Usage: $0 <host> install <target_host>"
        exit 1
    fi

    log "Installing system configuration using nixos-anywhere for host '${HOST}' to remote target: ${target_host}"
    write_secrets_nix

    # Install on target host using the using nixos-anywhere
    local cmd="nix run $ARGS github:nix-community/nixos-anywhere -- --impure --flake '${FLAKE_REF}#${HOST}' --target-host '${target_host}'"
    log_command "$cmd"
    if ! eval "$cmd"; then
        error "System installment using nixos-anywhere failed for host '${HOST}' to target: ${target_host}"
        return 1
    fi
    success "System installed using nixos-anywhere successfully for host '${HOST}' to target: ${target_host}"
}

# Main function
main() {
    # Check for --help first
    for arg in "$@"; do
        if [ "$arg" = "--help" ]; then
            parse_options "$@"
        fi
    done

    # Parse options first
    local remaining_args
    remaining_args=$(parse_options "$@")

    # Extract action and deploy target from remaining arguments
    local action=""
    local deploy_target=""

    # Parse remaining arguments: [action] [args]
    set -- $remaining_args
    while [[ $# -gt 0 ]]; do
        case $1 in
            --*)
                # Skip options that were already parsed
                shift
                ;;
            *)
                if [ -z "$action" ]; then
                    action="$1"
                else
                    deploy_target="$1"
                fi
                shift
                ;;
        esac
    done

    # Validate required HOST environment variable
    if [ -z "$HOST" ]; then
        error "HOST environment variable is required"
        echo "Usage: HOST=<host> $0 [OPTIONS] [ACTION] [ARGS]"
        echo "Use --help for more information"
        exit 1
    fi

    action="${action:-switch}"
    send_notification "info" "NixOS Rebuild" "Starting ${action} for ${HOST}..."

    log "Starting NixOS rebuild script"
    log "Host: ${HOST}"
    log "Flake directory: ${FLAKE_DIR}"
    log "Action: ${action}"
    if [ -n "$ARGS" ]; then
        log "Additional nix args: ${ARGS}"
    fi

    cd "${FLAKE_DIR}"

    # Load secrets (core functionality)
    load_secrets

    print_module_matrix

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
        "validate")
            validate_flake
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
            echo "Usage: HOST=<host> $0 [OPTIONS] {switch|build|dry-run|rollback|generations|validate|deploy|install}"
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
    if [ ${exit_code} -ne 0 ]; then
        if [ "$NOTIFIED_ERROR" = false ]; then
            send_notification "error" "NixOS Rebuild Failed" "Script exited with code ${exit_code}"
        fi
        log "Script failed with exit code ${exit_code}"
    fi
    log "Script finished"
}

trap cleanup EXIT

# Run main function with all arguments
main "$@"
