#!/bin/bash

# Shared helpers for the setup scripts: logging, running commands, backups and OS detection.
# No install logic lives here.

BACKUP_DIR="${BACKUP_DIR:-/tmp}"
LOG_FILE="/tmp/installation.log"
export PATH="$HOME/.local/bin:$PATH"

# ------------------------------------------------------------------------------
# Logging
# ------------------------------------------------------------------------------

log() {
    level="$1"
    shift
    echo ""
    if [ "$level" = "WARN" ]; then
        echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] [\033[33m$level\033[0m] $*" | tee -a "$LOG_FILE"
    elif [ "$level" = "ERROR" ]; then
        echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] [\033[31m$level\033[0m] $*" | tee -a "$LOG_FILE"
    else
        echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a "$LOG_FILE"
    fi
}

show_progress() {
    echo -n "$1..."
}

finish_progress() {
    exit_status=$?
    if [ $exit_status -eq 0 ]; then
        echo " Done"
    else
        echo " Failed"
    fi
    return $exit_status
}

# Used as the EXIT trap: trap 'cleanup ${LINENO} $?' EXIT
cleanup() {
    exit_code=$?
    line_no=$1
    error_code=$2
    if [ $exit_code -ne 0 ]; then
        log "ERROR" "Error on line $line_no. Exit code: $error_code"
    fi
    exit $exit_code
}

# ------------------------------------------------------------------------------
# Running commands
# ------------------------------------------------------------------------------

# Run a command, logging it and its output; returns 1 on failure
execute() {
    log "CMD" "$*"
    if ! OUTPUT=$("$@" 2>&1 | tee -a "$LOG_FILE"); then
        log "ERROR" "$OUTPUT"
        log "ERROR" "Failed to Execute $*"
        return 1
    fi
}

# Same as execute, with sudo unless we're already root (ROOT_MODE=true)
run_command() {
    if [ "$ROOT_MODE" = "true" ]; then
        execute "$@"
    else
        execute sudo "$@"
    fi
}

# ------------------------------------------------------------------------------
# Files
# ------------------------------------------------------------------------------

# Move a file, directory or link into $BACKUP_DIR, then remove it
backup_and_delete() {
    # Strip any trailing slashes so symlink checks don't incorrectly follow them
    file="${1%/}"

    # HARD CHECK: NEVER DELETE THESE DIRECTORIES
    if [ "$file" = "$HOME" ] || [ "$file" = "$HOME/.config" ] || [ "$file" = "$HOME/.local" ] || [ "$file" = "$HOME/.local/share" ]; then
        log "ERROR" "FATAL: Attempted to backup and delete a critical system directory: $file"
        exit 1
    fi

    if [ ! -e "$file" ] && [ ! -L "$file" ]; then
        return 0
    fi

    mkdir -p "$BACKUP_DIR"
    backup_path="$BACKUP_DIR/$(basename "$file")"

    if [ -L "$file" ]; then
        unlink "$file" || {
            log "ERROR" "Failed to remove symlink $file"
            return 4
        }
    else
        cp -a "$file" "$backup_path" || {
            log "ERROR" "Failed to backup $file"
            return 3
        }
        rm -rf "$file" || {
            log "ERROR" "Failed to delete $file"
            return 4
        }
        log "INFO" "Backed up $file to $backup_path"
    fi
}

# ------------------------------------------------------------------------------
# Environment detection
# ------------------------------------------------------------------------------

is_wsl() {
    [ -f /proc/sys/fs/binfmt_misc/WSLInterop ] || grep -qi microsoft /proc/version 2>/dev/null
}

OS_ID="unknown"
IS_ARCH=false
IS_DEBIAN=false
IS_FEDORA=false
IS_ATOMIC=false
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID=$ID
    if [ "$OS_ID" = "arch" ] || [ "$OS_ID" = "cachyos" ] || echo "${ID_LIKE:-}" | grep -qw "arch"; then
        IS_ARCH=true
    fi
    if [ "$OS_ID" = "ubuntu" ] || [ "$OS_ID" = "debian" ] || echo "${ID_LIKE:-}" | grep -qw -e "ubuntu" -e "debian"; then
        IS_DEBIAN=true
    fi
    if [ "$OS_ID" = "fedora" ] || echo "${ID_LIKE:-}" | grep -qw -e "fedora" -e "rhel"; then
        IS_FEDORA=true
    fi
fi
# Image-based (rpm-ostree / bootc) systems can't dnf install; packages are layered instead
if [ -e /run/ostree-booted ]; then
    IS_ATOMIC=true
fi
export OS_ID IS_ARCH IS_DEBIAN IS_FEDORA IS_ATOMIC
