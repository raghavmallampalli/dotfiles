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
    for dir in nvim tmux zsh yazi; do
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

install_tools_yay() {
    log "INFO" "Installing tools via yay..."

    show_progress "Installing essentials and tools via yay"
    
    # Combined package list
    local PACKAGES=(
        github-cli wget openssh aria2 curl rsync
        zip unzip p7zip
        cmake moreutils inetutils
        zsh tmux vim htop nvtop
        xclip jq stow gum copyq
        fzf ripgrep bat fd zoxide duf yazi-bin lazygit neovim
    )

    execute yay -S --needed --noconfirm "${PACKAGES[@]}" 
    
    finish_progress
}

install_yay() {
    log "INFO" "Starting yay installation..."

    if ! command -v yay >/dev/null 2>&1; then
        show_progress "Installing yay"
        # We use /tmp to avoid permission issues if the current directory is inside /root
        local YAY_BUILD_DIR="/tmp/yay-bin"
        if [ -d "$YAY_BUILD_DIR" ]; then rm -rf "$YAY_BUILD_DIR"; fi
        git clone https://aur.archlinux.org/yay-bin.git "$YAY_BUILD_DIR"

        local CURRENT_DIR=$(pwd)
        cd "$YAY_BUILD_DIR"

        if [ "$EUID" -eq 0 ]; then
            log "WARN" "Running makepkg as root. Creating temporary builder user..."
            if ! id -u builder >/dev/null 2>&1; then
                useradd -m builder
                echo "builder ALL=(ALL) NOPASSWD: ALL" >>/etc/sudoers
            fi
            chown -R builder:builder .
            su builder -c "makepkg -si --noconfirm"
        else
            makepkg -si --noconfirm
        fi

        cd "$CURRENT_DIR"
        rm -rf "$YAY_BUILD_DIR"
        finish_progress
    fi
}

install_apt_always() {
    log "INFO" "Installing always-essential packages for Debian/Ubuntu..."

    show_progress "Updating system packages"
    run_command apt update -y
    run_command apt upgrade -y
    run_command apt-get install git wget curl zip unzip 7zip stow -y
    finish_progress

    show_progress "Setting up GitHub CLI keyring"
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | run_command dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
    run_command chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | run_command tee /etc/apt/sources.list.d/github-cli.list >/dev/null
    finish_progress
    run_command apt-get install gh -y

    show_progress "Installing development and base tools"
    # Superset of tools
    run_command apt-get install build-essential g++ cmake cmake-curses-gui pkg-config checkinstall automake -y
    run_command apt-get install xclip jq autossh fonts-powerline aria2 rsync moreutils ca-certificates openssh-client inetutils-ping -y
    run_command apt-get install htop nvtop -y
    run_command apt-get install zsh vim tmux -y
    run_command apt-get install libevent-dev ncurses-dev bison -y
    finish_progress

    if is_wsl; then
        show_progress "Installing WSLU"
        run_command apt-get install wslu -y
        finish_progress
    fi
    
    # neovim: no other stable version exists via apt usually, using snap or bob is better but keeping snap here as per original
    run_command snap install nvim --classic
}

install_tools_binaries() {
    log "INFO" "Installing tools via Binaries (Manual)..."

    # FZF
    if ! command -v fzf >/dev/null 2>&1; then
        show_progress "Installing FZF"
        if [ ! -d "$HOME/.fzf" ]; then
            execute git clone --quiet --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf"
        fi
        execute "$HOME/.fzf/install" --all
        wget https://raw.githubusercontent.com/junegunn/fzf-git.sh/main/fzf-git.sh -qO "$HOME/.fzf-git.sh"
        finish_progress
    fi

    # Zoxide
    show_progress "Installing Zoxide"
    curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
    finish_progress

    # DUF
    show_progress "Installing DUF"
    url=$(wget "https://api.github.com/repos/muesli/duf/releases/latest" -qO- | grep browser_download_url | grep "linux_x86_64" | grep ".tar.gz" | head -n 1 | cut -d \" -f 4)
    wget "$url" -qO- | tar -xz -C /tmp/
    mv /tmp/duf "$HOME/.local/bin/"
    finish_progress

    # BAT
    show_progress "Installing BAT"
    url=$(wget "https://api.github.com/repos/sharkdp/bat/releases/latest" -qO- | grep browser_download_url | grep "gnu" | grep "x86_64" | grep "linux" | head -n 1 | cut -d \" -f 4)
    wget "$url" -qO- | tar -xz -C /tmp/
    mv /tmp/bat*/bat "$HOME/.local/bin/"
    finish_progress

    # FD
    show_progress "Installing FD"
    url=$(wget "https://api.github.com/repos/sharkdp/fd/releases/latest" -qO- | grep browser_download_url | grep "gnu" | grep "x86_64" | grep "linux" | head -n 1 | cut -d \" -f 4)
    wget "$url" -qO- | tar -xz -C /tmp
    mv /tmp/fd*/fd "$HOME/.local/bin/"
    finish_progress

    # RIPGREP
    show_progress "Installing Ripgrep"
    url=$(wget "https://api.github.com/repos/BurntSushi/ripgrep/releases/latest" -qO- | grep browser_download_url | grep "x86_64" | grep "linux" | head -n 1 | cut -d \" -f 4)
    wget "$url" -qO- | tar -xz -C /tmp/
    mv /tmp/ripgrep*/rg "$HOME/.local/bin/"
    finish_progress
    
    # GUM - Inlined here
    if ! command -v gum >/dev/null 2>&1; then
        show_progress "Installing Gum"
        url=$(wget "https://api.github.com/repos/charmbracelet/gum/releases/latest" -qO- | grep browser_download_url | grep "linux_x86_64" | grep ".tar.gz" | head -n 1 | cut -d \" -f 4)
        wget "$url" -qO- | tar -xz -C /tmp/
        # Use find to handle the versioned directory name
        local temp_gum_dir=$(find /tmp/ -maxdepth 1 -type d -name "gum_*" | head -n 1)
        mv "$temp_gum_dir/gum" "$HOME/.local/bin/"
        chmod +x "$HOME/.local/bin/gum"
        rm -rf "$temp_gum_dir"
        finish_progress
    fi

    # Yazi - via helper
    show_progress "Installing Yazi"
    wget -q https://github.com/sxyazi/yazi/releases/latest/download/yazi-x86_64-unknown-linux-musl.zip -O /tmp/yazi.zip
    unzip -oq /tmp/yazi.zip -d /tmp
    mv /tmp/yazi-x86_64-unknown-linux-musl/yazi "$HOME/.local/bin/"
    mv /tmp/yazi-x86_64-unknown-linux-musl/ya "$HOME/.local/bin/"
    chmod +x "$HOME/.local/bin/yazi"
    chmod +x "$HOME/.local/bin/ya"
    finish_progress
}

stow_custom_scripts() {
    show_progress "Stowing custom scripts to ~/.local/scripts"
    
    local TARGET_DIR="$HOME/.local/scripts"
    
    # Backup existing directory if it's not a symlink and exists
    if [ -d "$TARGET_DIR" ] && [ ! -L "$TARGET_DIR" ]; then
        log "INFO" "Backing up existing $TARGET_DIR to $TARGET_DIR.bak"
        mv "$TARGET_DIR" "$TARGET_DIR.bak"
    fi
    
    mkdir -p "$TARGET_DIR"
    
    # We use stow to symlink everything from ./scripts to ~/.local/scripts
    stow -d . -t "$TARGET_DIR" scripts
    
    finish_progress
}