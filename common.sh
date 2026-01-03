#!/bin/sh

# Constants and configuration
BACKUP_DIR="${BACKUP_DIR:-/tmp}"
LOG_FILE="/tmp/installation.log"
export PATH="$HOME/.local/bin:$PATH"

# Logging function
log() {
    level="$1"
    shift
    echo ""
    if [ "$level" = "WARN" ]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] [\033[33m$level\033[0m] $*" | tee -a "$LOG_FILE"
    elif [ "$level" = "ERROR" ]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] [\033[31m$level\033[0m] $*" | tee -a "$LOG_FILE"
    else
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a "$LOG_FILE"
    fi
}

# Progress indication
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

# Cleanup function
cleanup() {
    exit_code=$?
    line_no=$1
    error_code=$2

    # Always do cleanup
    log "INFO" "Cleaning up temporary files..."
    [ -f temp ] && rm -f temp
    [ -f /tmp/*.deb ] && rm -f /tmp/*.deb
    [ -f /tmp/miniconda.sh ] && rm -f /tmp/miniconda.sh
    log "INFO" "Done."

    # Only log error if there was one
    if [ $exit_code -ne 0 ]; then
        log "ERROR" "Error on line $line_no. Exit code: $error_code"
    fi

    exit $exit_code
}

# Function to run commands based on root/non-root mode
run_command() {
    if [ "$ROOT_MODE" = "true" ]; then
        execute "$@"
    else
        execute sudo "$@"
    fi
}

# Improved execute function
execute() {
    log "CMD" "$*"
    if ! OUTPUT=$("$@" 2>&1 | tee -a "$LOG_FILE"); then
        log "ERROR" "$OUTPUT"
        log "ERROR" "Failed to Execute $*"
        return 1
    fi
}

# Backup the file to backup directory and delete it
backup_and_delete() {
    file="$1"
    backup_path="$BACKUP_DIR/$(basename "$file")"

    # check if the file exists and is a regular file
    if [ ! -e "$file" ]; then
        log "INFO" "$file does not exist"
        return 0
    fi

    if is_symlink "$file"; then
        log "INFO" "$file is a symbolic link"
        if [ -f "$(readlink "$file")" ]; then
            cp -L "$file" "$backup_path" || {
                log "ERROR" "Failed to backup symlink target $file"
                return 3
            }
        fi
        rm "$file" || {
            log "ERROR" "Failed to remove symlink $file"
            return 4
        }
    elif [ "$(stat -c %h "$file")" -gt 1 ]; then
        log "INFO" "$file is a hard link"
        cp -L "$file" "$backup_path" || {
            log "ERROR" "Failed to backup hard link $file"
            return 3
        }
        unlink "$file" || {
            log "ERROR" "Failed to unlink hard link $file"
            return 4
        }
    else
        cp -L "$file" "$backup_path" || {
            log "ERROR" "Failed to backup $file"
            return 3
        }
        rm "$file" || {
            log "ERROR" "Failed to delete $file"
            return 4
        }
    fi
    log "INFO" "Backed up and removed $file"
}

# Improved dotfile installation
# Default behavior: Try hard link first, fall back to soft link if hard link fails
# This handles cross-filesystem scenarios automatically
install_dotfile() {
    src="$1"
    dest="$2"
    link="${3:-false}"
    if [ "$link" = "true" ]; then
        link=true
    else
        link=false
    fi

    show_progress "Installing $(basename "$src")"
    if [ ! -f "$src" ]; then
        log "ERROR" "Source file $src does not exist"
        finish_progress
        return 1
    fi

    backup_and_delete "$dest"

    if [ "$link" = "true" ]; then
        # Convert relative source path to absolute path for symlink
        if [[ "$src" != /* ]]; then
            src="$(realpath "$src")"
        fi
        ln -s "$src" "$dest"
        log "INFO" "Created soft link for $(basename "$src")"
    else
        # Try hard link first, fall back to soft link if it fails
        if ln "$src" "$dest" 2>/dev/null; then
            log "INFO" "Created hard link for $(basename "$src")"
        else
            # Hard link failed, fall back to soft link
            log "INFO" "Hard link failed, falling back to soft link for $(basename "$src")"
            # Convert relative source path to absolute path for symlink
            if [[ "$src" != /* ]]; then
                src="$(realpath "$src")"
            fi
            ln -s "$src" "$dest"
        fi
    fi
    finish_progress
}

# WSL detection
is_wsl() {
    if [ -f /proc/sys/fs/binfmt_misc/WSLInterop ] || \
       grep -qi microsoft /proc/version 2>/dev/null; then
        return 0
    fi
    return 1
}

# Configuration backup
backup_configs() {
    backup_dir="$BACKUP_DIR/config_backup_$(date +%Y%m%d_%H%M%S)"
    show_progress "Backing up configurations"
    mkdir -p "$backup_dir"
    for file in .zshrc .bashrc .vimrc .tmux.conf .zshenv; do
        if [ -f "$HOME/$file" ]; then
            cp "$HOME/$file" "$backup_dir/"
        fi
    done

    # Backup XDG configs
    for dir in nvim tmux zsh yazi hypr; do
        if [ -d "$HOME/.config/$dir" ]; then
             cp -r "$HOME/.config/$dir" "$backup_dir/$dir"
        fi
    done
    log "INFO" "Configurations backed up to $backup_dir"
    finish_progress
}

is_symlink() {
    file="$1"
    if [ -L "$file" ]; then
        return 0
    fi
    return 1
}
