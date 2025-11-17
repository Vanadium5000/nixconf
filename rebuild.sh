#!/usr/bin/env bash
set -euo pipefail

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

# Load secrets from password-store
load_secrets() {
    log "Loading secrets from password-store..."

    if ! command_exists pass; then
        error "password-store (pass) is not installed. Please install it first."
        return 1
    fi

    # Load password hash
    if PASSWORD_HASH=$(pass "system/matrix/hashedPassword" 2>/dev/null); then
        export SECRETS_PASSWORD_HASH="${PASSWORD_HASH}"
        success "Loaded PASSWORD_HASH from password-store"
    else
        warn "Could not load PASSWORD_HASH from password-store. Using environment variable if set."
    fi

    # Add more secrets here as needed
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
        nixos-rebuild build --flake "${FLAKE_DIR}#${HOST}" --impure
        success "System backup created"
    fi
}

# Validate flake (optional)
validate_flake() {
    log "Validating flake configuration..."
    if ! nix flake check "${FLAKE_DIR}" --impure; then
        error "Flake validation failed"
        return 1
    fi
    success "Flake validation passed"
}

# Build system
build_system() {
    log "Building system configuration for host: ${HOST}"
    local cmd="nixos-rebuild build --flake '${FLAKE_DIR}#${HOST}' --impure"
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
    local cmd="nixos-rebuild dry-run --flake '${FLAKE_DIR}#${HOST}' --impure"
    log_command "$cmd"
    if ! eval "$cmd"; then
        error "Dry run failed for host: ${HOST}"
        return 1
    fi
    success "Dry run completed successfully for host: ${HOST}"
}

# Switch to new system
switch_system() {
    log "Switching to new system configuration for host: ${HOST}"
    local env_vars=""
    if [ -n "${SECRETS_PASSWORD_HASH:-}" ]; then
        env_vars="SECRETS_PASSWORD_HASH='${SECRETS_PASSWORD_HASH}' "
    fi

    local cmd="${env_vars}sudo nixos-rebuild switch --flake '${FLAKE_DIR}#${HOST}' --impure"
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
    local cmd="sudo nixos-rebuild --rollback switch"
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
Usage: HOST=<host> $0 [OPTIONS] [ACTION] [ARGS]

Environment Variables:
  HOST        Target host configuration (required)

Arguments:
  ACTION      Action to perform (default: switch)
  ARGS        Additional arguments for deploy action

Actions:
  switch       Switch to new system configuration (default)
  build        Build system configuration without switching
  dry-run      Perform dry run
  rollback     Rollback to previous generation
  generations  Show system generations
  validate     Validate flake configuration
  deploy       Deploy to remote host (requires TARGET_HOST argument)

Options:
  --log-file    Enable logging to file
  --git-backup  Enable automatic git backup commits
  --validate    Enable flake validation
  --backup      Enable system backup before switch
  --help        Show this help message

Examples:
  HOST=macbook $0 switch                    # Switch local macbook system
  HOST=macbook $0 build                     # Build macbook configuration
  HOST=macbook $0 deploy root@192.168.1.100 # Deploy to remote host
  HOST=legion5i $0 --validate switch        # Validate before switching legion5i
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
    local env_vars=""
    if [ -n "${SECRETS_PASSWORD_HASH:-}" ]; then
        env_vars="SECRETS_PASSWORD_HASH='${SECRETS_PASSWORD_HASH}' "
    fi

    local cmd="${env_vars}nixos-rebuild switch --target-host '${target_host}' --flake '${FLAKE_DIR}#${HOST}' --impure"
    log_command "$cmd"
    if ! eval "$cmd"; then
        error "System deployment failed for host '${HOST}' to target: ${target_host}"
        return 1
    fi
    success "System deployed successfully for host '${HOST}' to target: ${target_host}"
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
        *)
            error "Unknown action: ${action}"
            echo "Usage: HOST=<host> $0 [OPTIONS] {switch|build|dry-run|rollback|generations|validate|deploy}"
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