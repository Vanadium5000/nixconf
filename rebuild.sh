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
HOST="${HOST:-macbook}"

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
    log "Building system configuration..."
    if ! nixos-rebuild build --flake "${FLAKE_DIR}#${HOST}" --impure; then
        error "System build failed"
        return 1
    fi
    success "System built successfully"
}

# Dry run
dry_run() {
    log "Performing dry run..."
    if ! nixos-rebuild dry-run --flake "${FLAKE_DIR}#${HOST}" --impure; then
        error "Dry run failed"
        return 1
    fi
    success "Dry run completed successfully"
}

# Switch to new system
switch_system() {
    log "Switching to new system configuration..."
    local env_vars=""
    if [ -n "${SECRETS_PASSWORD_HASH:-}" ]; then
        env_vars="SECRETS_PASSWORD_HASH='${SECRETS_PASSWORD_HASH}' "
    fi

    if ! sudo sh -c "${env_vars}nixos-rebuild switch --flake '${FLAKE_DIR}#${HOST}' --impure"; then
        error "System switch failed"
        return 1
    fi
    success "System switched successfully"
}

# Rollback system
rollback_system() {
    log "Rolling back to previous system generation..."
    if ! sudo nixos-rebuild --rollback switch; then
        error "System rollback failed"
        return 1
    fi
    success "System rolled back successfully"
}

# Show generations
show_generations() {
    log "Current system generations:"
    sudo nix-env --list-generations --profile /nix/var/nix/profiles/system | tail -10
}

# Parse command-line options
parse_options() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help)
                cat << EOF
Usage: $0 [OPTIONS] [ACTION]

Actions:
  switch     Switch to new system configuration (default)
  build      Build system configuration without switching
  dry-run    Perform dry run
  rollback   Rollback to previous generation
  generations Show system generations
  validate   Validate flake configuration

Options:
  --log-file    Enable logging to file
  --git-backup  Enable automatic git backup commits
  --validate    Enable flake validation
  --backup      Enable system backup before switch
  --help        Show this help message
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

# Main function
main() {
    # Parse options first
    parse_options "$@"

    # Get remaining arguments after options
    local action=""
    while [[ $# -gt 0 ]]; do
        case $1 in
            --*)
                shift
                ;;
            *)
                action="$1"
                break
                ;;
        esac
    done

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
        *)
            error "Unknown action: ${action}"
            echo "Usage: $0 [OPTIONS] {switch|build|dry-run|rollback|generations|validate}"
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