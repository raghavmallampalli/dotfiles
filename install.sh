#!/bin/bash

set -e
set -u
set -o pipefail

source "$(dirname "$0")/common.sh"

trap 'cleanup ${LINENO} $?' EXIT

# Parse command line arguments
# (No logic flags remaining, only help)

# Function to show help
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
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
        help)
            show_help
            ;;
        *)
            echo "Unknown option: --${OPTARG}"
            show_help
            ;;
        esac
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

# Helper/wrapper for running yay is deprecated/removed. We call yay directly.

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

install_custom_scripts() {
    show_progress "Installing custom management scripts"
    run_command cp "./scripts/imv" "$HOME/.local/bin/imv"
    run_command chmod +x "$HOME/.local/bin/imv"
    run_command cp "./scripts/launch-webapp" "$HOME/.local/bin/launch-webapp"
    run_command chmod +x "$HOME/.local/bin/launch-webapp"
    run_command cp "./scripts/manage-webapp" "$HOME/.local/bin/manage-webapp"
    run_command chmod +x "$HOME/.local/bin/manage-webapp"
    run_command cp "./scripts/niri-to-kanshi" "$HOME/.local/bin/niri-to-kanshi"
    run_command chmod +x "$HOME/.local/bin/niri-to-kanshi"
    finish_progress
}


# -----------------------------------------------------------------------------
# Main Execution
# -----------------------------------------------------------------------------

main() {
    log "INFO" "Starting main execution..."
    
    # UV
    show_progress "Installing UV"
    curl -LsSf https://astral.sh/uv/install.sh | sh
    echo 'eval "$(uv generate-shell-completion zsh)"' >>"$HOME/.zshrc"
    finish_progress
    
    # Custom Scripts (Always install these)
    install_custom_scripts

    if [[ "$OS_ID" == "arch" ]]; then
        log "INFO" "Installing bootstrap packages for Arch Linux..."

        show_progress "Updating system and installing prerequisites"
        # Basic tools needed to bootstrap the rest
        run_command pacman -Sy --needed --noconfirm git base-devel ca-certificates
        finish_progress
        
        install_yay
        install_tools_yay
        
    elif [[ "$OS_ID" == "ubuntu" ]] || [[ "$OS_ID" == "debian" ]]; then
        # On Ubuntu, we start with minimal system setup, then use binaries for tools
        install_apt_always
        install_tools_binaries
    else
        log "WARN" "Unsupported OS for package manager: $OS_ID. Attempting binary installation for tools..."
        install_tools_binaries
    fi

    log "INFO" "Installation completed."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
