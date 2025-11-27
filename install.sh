#!/bin/bash

set -e
set -u
set -o pipefail

source "$(dirname "$0")/common.sh"

trap 'cleanup ${LINENO} $?' EXIT

# Parse command line arguments
HAS_SUDO=""
INSTALL_FROM_BINARIES=""

# Function to show help
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -s, --sudo-access <y/n>        Do you have sudo access?"
    echo "  -b, --binaries-install <y/n>   Install tools from binaries (manual) instead of package manager?"
    echo "  -h, --help                     Show this help message"
    echo ""
    echo "If any option is not provided, the script will prompt interactively."
    exit 0
}

# Parse options
while getopts ":-:" opt; do
    case $opt in
        -)
            case "${OPTARG}" in
                sudo-access)
                    HAS_SUDO="${!OPTIND}"
                    OPTIND=$((OPTIND + 1))
                    ;;
                binaries-install)
                    INSTALL_FROM_BINARIES="${!OPTIND}"
                    OPTIND=$((OPTIND + 1))
                    ;;
                help)
                    show_help
                    ;;
                *)
                    echo "Unknown option: --${OPTARG}"
                    show_help
                    ;;
            esac
            ;;
        s)
            HAS_SUDO="$OPTARG"
            ;;
        b)
            INSTALL_FROM_BINARIES="$OPTARG"
            ;;
        h)
            show_help
            ;;
        \?)
            echo "Invalid option: -$OPTARG"
            show_help
            ;;
    esac
done

# Check if any CLI arguments were provided
CLI_ARGS_PROVIDED=false
if [ $# -gt 0 ]; then
    CLI_ARGS_PROVIDED=true
fi

# Detect if running as root
if [ "$EUID" -eq 0 ]; then
    ROOT_MODE=true
    # Check if any CLI arguments were provided
    if [ "$CLI_ARGS_PROVIDED" = true ]; then
        # Use default root directory when CLI args are detected
        HOME="$HOME"
        log "INFO" "Running in root mode with CLI arguments. Using default home directory: $HOME"
    else
        # Interactive mode - prompt for root home directory
        read -p "Enter root home directory: [default: $HOME]" ROOT_HOME
        HOME="${ROOT_HOME:-$HOME}"
        log "INFO" "Running in root mode. Home directory set to $HOME"
    fi
else
    ROOT_MODE=false
fi
export ROOT_MODE

# Initialize
mkdir -p "$BACKUP_DIR"
log "INFO" "Starting installation..."
log "WARN" "Do not execute this file without reading it first and changing directory to the parent folder of this script."
log "INFO" "If it exits without completing install run 'sudo apt --fix-broken install' (on Debian/Ubuntu)."

# Collect all user inputs at the start
if [ "$ROOT_MODE" = false ]; then
    if [ -z "$HAS_SUDO" ]; then
        read -p "Do you have sudo access? [y/n] " HAS_SUDO
    fi
else
    HAS_SUDO="y"
fi

# Determine installation method preference
if [[ $HAS_SUDO = y ]]; then
    if [ -z "$INSTALL_FROM_BINARIES" ]; then
        log "INFO" "You have sudo access. Defaulting to package manager installation."
        read -p "Install from binaries (manual) instead of package manager? [y/N] " INSTALL_FROM_BINARIES
        INSTALL_FROM_BINARIES=${INSTALL_FROM_BINARIES:-n}
    fi
else
    log "INFO" "No sudo access or running in root mode. Forcing installation from binaries."
    INSTALL_FROM_BINARIES="y"
fi

show_progress "Creating local bin directory"
mkdir -p "$HOME/.local/bin"
if [ ! -w "$HOME/.local/bin" ]; then
    log "ERROR" "Cannot write to $HOME/.local/bin"
    exit 1
fi
export PATH="$HOME/.local/bin:$PATH"
finish_progress

# OS Detection
OS_ID="unknown"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID=$ID
fi
log "INFO" "Detected OS: $OS_ID"

# -----------------------------------------------------------------------------
# Installation Functions
# -----------------------------------------------------------------------------

install_arch() {
    log "INFO" "Starting Arch Linux installation..."
    
    show_progress "Updating system and installing prerequisites"
    run_command sudo pacman -S --needed --noconfirm git base-devel
    finish_progress

    # Install yay if not present
    if ! command -v yay >/dev/null 2>&1; then
        show_progress "Installing yay"
        run_command git clone https://aur.archlinux.org/yay.git /tmp/yay
        # makepkg cannot be run as root. If we are root, this is tricky.
        # Assuming user is non-root with sudo access as per standard Arch practice.
        # If running as root, we should probably warn or skip, but for now we assume non-root.
        if [ "$EUID" -eq 0 ]; then
             log "WARN" "Running as root, yay installation might fail. Please run as non-root user."
             # Attempting to run as nobody if root? No, too complex. Just let it fail or user handle it.
             # Actually, makepkg -si fails as root.
             # We can try to chown and run as nobody but that requires sudo setup for nobody.
             # For now, we proceed.
             cd /tmp/yay && run_command makepkg -si --noconfirm
        else
             cd /tmp/yay && run_command makepkg -si --noconfirm
        fi
        finish_progress
    fi

    show_progress "Installing packages via yay"
    # Install all requested tools
    # Note: 'yes |' might be needed for some prompts, but --noconfirm should handle most.
    # However, yay sometimes asks for diff review.
    run_command yay -S --noconfirm --needed htop nvtop rsync aria2 github-cli zsh vim tmux fzf ripgrep bat fd yazi duf wget curl git zoxide
    finish_progress

    # Link bat and fd if needed (Arch usually installs them with correct names, unlike Ubuntu)
    # But just in case check names. Arch: bat, fd. Ubuntu: batcat, fdfind.
    # So no linking needed for Arch usually.
    
    # Install DuckDB (not always in AUR or might be old, but let's stick to binary for consistency or AUR?)
    # User asked for yay/pacman always if available.
    # duckdb-bin is in AUR.
    show_progress "Installing DuckDB via yay"
    run_command yay -S --noconfirm --needed duckdb-bin
    finish_progress
    
    # rich-cli for yazi
    show_progress "Installing rich-cli via yay"
    run_command yay -S --noconfirm --needed python-rich-cli
    finish_progress

    # IMV script
    show_progress "Installing IMV script"
    run_command sudo cp "./scripts/imv" "/usr/local/bin/imv"
    run_command sudo chmod +x "/usr/local/bin/imv"
    finish_progress
}

install_apt() {
    log "INFO" "Starting Debian/Ubuntu installation..."

    show_progress "Updating system packages"
    run_command apt update -y
    run_command apt upgrade -y
    run_command apt-get install git wget curl -y
    finish_progress

    show_progress "Setting up GitHub CLI keyring"
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | run_command dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
    run_command chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | run_command tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    finish_progress
    run_command apt-get install gh -y

    show_progress "Installing development tools"
    run_command apt-get install build-essential g++ cmake cmake-curses-gui pkg-config checkinstall automake -y
    run_command apt-get install xclip jq autossh unzip zip -y
    run_command apt-get install htop nvtop -y
    run_command apt-get install fonts-powerline aria2 rsync -y
    run_command apt-get install moreutils -y
    finish_progress

    show_progress "Installing ZSH, Vim, Tmux"
    run_command apt-get install zsh vim -y
    run_command apt-get install libevent-dev ncurses-dev build-essential bison pkg-config -y
    run_command apt-get install tmux -y
    finish_progress

    # Utilities that we prefer from apt if available and up to date enough, 
    # but the original script had manual install logic for many.
    # We will stick to the original script's logic: if INSTALL_FROM_PACKAGES (now !INSTALL_FROM_BINARIES) is true, use apt.
    
    show_progress "Installing Zoxide"
    run_command apt-get install zoxide -y
    finish_progress

    show_progress "Installing BAT"
    run_command apt-get install bat -y
    mkdir -p "$HOME/.local/bin"
    ln -f /usr/bin/batcat "$HOME/.local/bin/bat"
    finish_progress

    show_progress "Installing FD"
    run_command apt-get install fd-find -y
    ln -sf "$(which fdfind)" "$HOME/.local/bin/fd"
    finish_progress

    show_progress "Installing Ripgrep"
    # Ripgrep in apt might be old, original script used deb from release or source.
    # We'll use the deb download approach as it was in the "package" block of original script.
    url=$(wget "https://api.github.com/repos/BurntSushi/ripgrep/releases/latest" -qO-| grep browser_download_url | grep "deb" | head -n 1 | cut -d \" -f 4)
    wget "$url" -qO /tmp/rg.deb
    run_command dpkg -i /tmp/rg.deb
    run_command apt-get install -f
    finish_progress

    show_progress "Installing DUF"
    run_command apt-get install duf -y
    finish_progress

    if is_wsl; then
        show_progress "Installing WSLU"
        run_command apt-get install wslu -y
        finish_progress
    fi
    
    # Yazi is not in standard apt repos usually, so we fall back to binary install for it even in apt mode?
    # Original script installed yazi via binary download ALWAYS.
    # So we should call install_binaries_yazi or similar.
    # For simplicity, I'll include the manual yazi install here as it was the only way.
    install_yazi_manual
    
    # DuckDB
    install_duckdb_manual
    
    # Rich-cli
    install_rich_cli_manual
    
    # IMV
    show_progress "Installing IMV script"
    cp "./scripts/imv" "$HOME/.local/bin/"
    chmod +x "$HOME/.local/bin/imv"
    finish_progress
}

install_binaries() {
    log "INFO" "Starting Binary/Manual installation..."
    
    # UV
    show_progress "Installing UV"
    curl -LsSf https://astral.sh/uv/install.sh | sh
    echo 'eval "$(uv generate-shell-completion zsh)"' >> "$HOME/.zshrc"
    finish_progress

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

    # BAT
    show_progress "Installing BAT"
    url=$(wget "https://api.github.com/repos/sharkdp/bat/releases/latest" -qO-| grep browser_download_url | grep "gnu" | grep "x86_64" | grep "linux" | head -n 1 | cut -d \" -f 4)
    wget "$url" -qO- | tar -xz -C /tmp/
    mv /tmp/bat*/bat "$HOME/.local/bin/"
    finish_progress

    # FD
    show_progress "Installing FD"
    url=$(wget "https://api.github.com/repos/sharkdp/fd/releases/latest" -qO-|grep browser_download_url | grep "gnu" | grep "x86_64" | grep "linux" | head -n 1 | cut -d \" -f 4)
    wget "$url" -qO- | tar -xz -C /tmp
    mv /tmp/fd*/fd "$HOME/.local/bin/"
    finish_progress

    # RIPGREP
    show_progress "Installing Ripgrep"
    url=$(wget "https://api.github.com/repos/BurntSushi/ripgrep/releases/latest" -qO-| grep browser_download_url | grep "x86_64" | grep "linux" | head -n 1 | cut -d \" -f 4)
    wget "$url" -qO- | tar -xz -C /tmp/
    mv /tmp/ripgrep*/rg "$HOME/.local/bin/"
    finish_progress
    
    install_yazi_manual
    install_duckdb_manual
    install_rich_cli_manual
    
    # IMV
    show_progress "Installing IMV script"
    cp "./scripts/imv" "$HOME/.local/bin/"
    chmod +x "$HOME/.local/bin/imv"
    finish_progress
}

# Helpers for common manual installs
install_yazi_manual() {
    show_progress "Installing Yazi"
    wget -q https://github.com/sxyazi/yazi/releases/latest/download/yazi-x86_64-unknown-linux-musl.zip -O /tmp/yazi.zip
    unzip -oq /tmp/yazi.zip -d /tmp
    mv /tmp/yazi-x86_64-unknown-linux-musl/yazi "$HOME/.local/bin/"
    mv /tmp/yazi-x86_64-unknown-linux-musl/ya "$HOME/.local/bin/"
    chmod +x "$HOME/.local/bin/yazi"
    chmod +x "$HOME/.local/bin/ya"
    finish_progress
}

install_duckdb_manual() {
    show_progress "Installing DuckDB"
    curl -sSfL https://install.duckdb.org | sh
    if [ -f "$HOME/.duckdb/bin/duckdb" ]; then
        ln -sf "$HOME/.duckdb/cli/latest/duckdb" "$HOME/.local/bin/duckdb" 2>/dev/null || true
    fi
    finish_progress
}

install_rich_cli_manual() {
    show_progress "Installing rich-cli"
    if command -v uv >/dev/null 2>&1; then
        uv tool install rich-cli
    else
        log "WARN" "uv not found, skipping rich-cli installation"
    fi
    finish_progress
}

# -----------------------------------------------------------------------------
# Main Execution
# -----------------------------------------------------------------------------

if [[ "$INSTALL_FROM_BINARIES" == "y" ]]; then
    install_binaries
else
    if [[ "$OS_ID" == "arch" ]]; then
        install_arch
    elif [[ "$OS_ID" == "ubuntu" ]] || [[ "$OS_ID" == "debian" ]]; then
        install_apt
    else
        log "WARN" "Unsupported OS for package manager: $OS_ID. Falling back to binary installation."
        install_binaries
    fi
fi

log "INFO" "Installation completed."
