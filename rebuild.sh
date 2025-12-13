#!/usr/bin/env bash
set -euo pipefail
shopt -s expand_aliases

# Simplified NixOS Rebuild Script
# Core features: Secret loading, colored logging, basic rebuild actions
# Optional features: Controlled by command-line flags

# Use rofi for askpass
ROFI_CMD='/run/current-system/sw/bin/rofi-askpass'
if command -v "$ROFI_CMD" &> /dev/null; then
    export SUDO_ASKPASS="$ROFI_CMD"
    alias sudo='sudo -A'
fi

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLAKE_DIR="${SCRIPT_DIR}"
HOST="${HOST:-}"
ARGS="${ARGS:-}"

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

# Logging functions
log() {
    local msg="$*"
    if [ -n "$LOG_FILE" ]; then
        echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $msg" | tee -a "$LOG_FILE"
    else
        echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $msg"
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
    # Example additional secrets (uncomment and modify as needed):
    # ["API_KEY"]="services/api/key"
    # ["DATABASE_PASSWORD"]="database/prod/password"
    # ["SSH_PRIVATE_KEY"]="ssh/private_key"
    # ["WIFI_PASSWORD"]="network/wifi/home"
    # ["EMAIL_PASSWORD"]="email/personal"
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
        echo "{ flake.secrets = {"
        for env_var in "${!SECRETS_MAP[@]}"; do
            local var_name="$env_var"
            local var_value="${!var_name:-}"
            if [ -n "$var_value" ]; then
                # Escape double quotes and backslashes for Nix
                escaped_value=$(printf '%s' "$var_value" | sed 's/\\/\\\\/g; s/"/\\"/g')
                echo "  ${var_name} = \"${escaped_value}\";"
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
    if ! nix flake check "path:${FLAKE_DIR}" --impure $ARGS; then
        error "Flake validation failed"
        return 1
    fi
    success "Flake validation passed"
}

# Build system
build_system() {
    log "Building system configuration for host: ${HOST}"
    local cmd="nixos-rebuild build --flake 'path:${FLAKE_DIR}#${HOST}' --impure $ARGS"
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
    local cmd="nixos-rebuild dry-run --flake 'path:${FLAKE_DIR}#${HOST}' --impure $ARGS"
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

    local cmd="sudo nixos-rebuild switch --flake 'path:${FLAKE_DIR}#${HOST}' --impure $ARGS"
    log_command "$cmd"
    if ! eval "$cmd"; then
        error "System switch failed for host: ${HOST}"
        return 1
    fi
    success "System switched successfully for host: ${HOST}"
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
deploy_system() {
    local target_host="$1"
    if [ -z "$target_host" ]; then
        error "deploy action requires TARGET_HOST argument"
        echo "Usage: $0 <host> deploy <target_host>"
        exit 1
    fi

    log "Deploying system configuration for host '${HOST}' to remote target: ${target_host}"
    write_secrets_nix

    # Deploy on target host using the target host to build packages, etc, using sudo (on normal user rather than root)
    # Use --build-host '${target_host}' to also build on target
    local cmd="nixos-rebuild switch --target-host '${target_host}' --ask-sudo-password  --flake 'path:${FLAKE_DIR}#${HOST}' --impure $ARGS"
    log_command "$cmd"
    if ! eval "$cmd"; then
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

    log "Installing system configuration using nixos-anywhere for host '${HOST}' to remote target: ${target_host}"
    write_secrets_nix

    # Install on target host using the using nixos-anywhere
    local cmd="nix run $ARGS github:nix-community/nixos-anywhere -- --flake 'path:${FLAKE_DIR}#${HOST}' --target-host '${target_host}'"
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

    log "Starting NixOS rebuild script"
    log "Host: ${HOST}"
    log "Flake directory: ${FLAKE_DIR}"
    log "Action: ${action}"
    if [ -n "$ARGS" ]; then
        log "Additional nix args: ${ARGS}"
    fi

    # Load secrets (core functionality)
    load_secrets

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
}

# Cleanup on exit
cleanup() {
    local exit_code=$?
    if [ ${exit_code} -ne 0 ]; then
        error "Script failed with exit code ${exit_code}"
    fi
    log "Script finished"
}

trap cleanup EXIT

# Run main function with all arguments
main "$@"