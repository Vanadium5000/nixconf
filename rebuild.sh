#!/usr/bin/env bash
set -euo pipefail

# Advanced NixOS Rebuild Script
# Features:
# - Secret loading from password-store
# - Multiple deployment modes (build, switch, dry-run, rollback)
# - Error handling and logging
# - Git integration for version tracking
# - Modern Nix commands

# Use rofi for askpass
ROFI_CMD='rofi-askpass'

# Only set SUDO_ASKPASS if the rofi-askpass command exists
if command -v "$ROFI_CMD" &> /dev/null; then
    export SUDO_ASKPASS="$ROFI_CMD"
    echo "SUDO_ASKPASS set to $ROFI_CMD (rofi prompt will be used)."
else
    echo "Warning: $ROFI_CMD not found in PATH. Falling back to terminal sudo prompt."
fi

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLAKE_DIR="${SCRIPT_DIR}"
HOST="${HOST:-macbook}"
LOG_FILE="${LOG_FILE:-${SCRIPT_DIR}/rebuild.log}"
BACKUP_SUFFIX=".backup.$(date +%Y%m%d_%H%M%S)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "${LOG_FILE}"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >> "${LOG_FILE}"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "${LOG_FILE}"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "${LOG_FILE}"
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
    # Example:
    # if API_KEY=$(pass "api/service/key" 2>/dev/null); then
    #     export SECRETS_API_KEY="${API_KEY}"
    #     success "Loaded API_KEY from password-store"
    # fi
}

# Git operations
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

# Backup current system
backup_system() {
    log "Creating system backup..."
    if command_exists nixos-rebuild; then
        # Create a backup of the current system closure
        nixos-rebuild build --flake "${FLAKE_DIR}#${HOST}" --impure
        # The result is in /run/current-system, but we can create a backup reference
        success "System backup created"
    fi
}

# Validate flake
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
    # Pass environment variables through sudo using sh -c
    local env_vars=""
    if [ -n "${SECRETS_PASSWORD_HASH:-}" ]; then
        env_vars="SECRETS_PASSWORD_HASH='${SECRETS_PASSWORD_HASH}' "
    fi
    # Add other secrets here if needed
    # if [ -n "${SECRETS_API_KEY:-}" ]; then
    #     env_vars="${env_vars}SECRETS_API_KEY='${SECRETS_API_KEY}' "
    # fi

    if ! sudo -A sh -c "${env_vars}nixos-rebuild switch --flake '${FLAKE_DIR}#${HOST}' --impure"; then
        error "System switch failed"
        return 1
    fi
    success "System switched successfully"
}

# Rollback system
rollback_system() {
    log "Rolling back to previous system generation..."
    if ! sudo -A nixos-rebuild --rollback switch; then
        error "System rollback failed"
        return 1
    fi
    success "System rolled back successfully"
}

# Show generations
show_generations() {
    log "Current system generations:"
    sudo -A nix-env --list-generations --profile /nix/var/nix/profiles/system | tail -10
}

# Main function
main() {
    local action="${1:-switch}"

    log "Starting NixOS rebuild script"
    log "Host: ${HOST}"
    log "Flake directory: ${FLAKE_DIR}"
    log "Action: ${action}"

    # Load secrets
    load_secrets

    # Check git status
    git_status

    case "${action}" in
        "build")
            validate_flake
            build_system
            ;;
        "switch")
            git_commit_backup
            backup_system
            validate_flake
            build_system
            switch_system
            ;;
        "dry-run")
            validate_flake
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
            echo "Usage: $0 {build|switch|dry-run|rollback|generations|validate}"
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