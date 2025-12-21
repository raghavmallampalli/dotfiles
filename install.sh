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

# Helper for running yay
run_yay() {
    if [ "$EUID" -eq 0 ]; then
        execute su builder -c "yay $*"
    else
        execute yay "$@"
    fi
}

install_yay_always() {
    log "INFO" "Installing bootstrap packages for Arch Linux..."
    
    show_progress "Updating system and installing prerequisites"
    # Basic tools needed to bootstrap the rest
    run_command pacman -Sy --needed --noconfirm git base-devel ca-certificates
    finish_progress
}

install_yay_tools_always() {
    log "INFO" "Installing always-essential packages via yay..."

    show_progress "Installing essentials and base tools via yay"
    # Essential tools and superset
    run_yay -S --needed --noconfirm wget curl zip unzip p7zip
    run_yay -S --needed --noconfirm github-cli aria2 openssh inetutils zsh tmux vim htop nvtop rsync xclip jq cmake moreutils
    finish_progress

    # IMV script
    show_progress "Installing IMV script"
    run_command sudo cp "./scripts/imv" "/usr/local/bin/imv"
    run_command sudo chmod +x "/usr/local/bin/imv"
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
                echo "builder ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
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

install_arch_choice_tools() {
    log "INFO" "Installing 'choice' packages via yay"
    run_yay -S --noconfirm --needed fzf ripgrep bat fd zoxide duf yazi-bin duckdb-bin
    finish_progress
}

install_apt_always() {
    log "INFO" "Installing always-essential packages for Debian/Ubuntu..."

    show_progress "Updating system packages"
    run_command apt update -y
    run_command apt upgrade -y
    run_command apt-get install git wget curl zip unzip 7zip -y
    finish_progress

    show_progress "Setting up GitHub CLI keyring"
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | run_command dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
    run_command chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | run_command tee /etc/apt/sources.list.d/github-cli.list > /dev/null
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

    install_rich_cli_manual

    # IMV
    show_progress "Installing IMV script"
    cp "./scripts/imv" "$HOME/.local/bin/"
    chmod +x "$HOME/.local/bin/imv"
    finish_progress
}

install_apt() {
    log "INFO" "Starting Debian/Ubuntu installation (APT route)..."

    show_progress "Installing 'choice' packages via apt"
    run_command apt-get install zoxide bat -y
    
    # FD
    run_command apt-get install fd-find -y
    ln -sf "$(which fdfind)" "$HOME/.local/bin/fd"

    # Ripgrep
    url=$(wget "https://api.github.com/repos/BurntSushi/ripgrep/releases/latest" -qO-| grep browser_download_url | grep "deb" | head -n 1 | cut -d \" -f 4)
    wget "$url" -qO /tmp/rg.deb
    run_command dpkg -i /tmp/rg.deb
    run_command apt-get install -f

    # DUF
    run_command apt-get install duf -y
    finish_progress

    # FZF
    if ! command -v fzf >/dev/null 2>&1; then
        show_progress "Installing FZF"
        run_command apt-get install fzf -y
        finish_progress
    fi

    # Yazi and DuckDB (no apt package for Yazi usually, and DuckDB is often old)
    install_yazi_manual
    install_duckdb_manual
}

install_binaries() {
    log "INFO" "Starting Binary/Manual installation (Choice route)..."
    
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
    url=$(wget "https://api.github.com/repos/muesli/duf/releases/latest" -qO-| grep browser_download_url | grep "linux_x86_64" | grep ".tar.gz" | head -n 1 | cut -d \" -f 4)
    wget "$url" -qO- | tar -xz -C /tmp/
    mv /tmp/duf "$HOME/.local/bin/"
    finish_progress

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

# UV
show_progress "Installing UV"
curl -LsSf https://astral.sh/uv/install.sh | sh
echo 'eval "$(uv generate-shell-completion zsh)"' >> "$HOME/.zshrc"
finish_progress

if [[ "$OS_ID" == "arch" ]]; then
    install_yay_always
    install_yay
    install_yay_tools_always
    install_rich_cli_manual
elif [[ "$OS_ID" == "ubuntu" ]] || [[ "$OS_ID" == "debian" ]]; then
    install_apt_always
fi

if [[ "$INSTALL_FROM_BINARIES" == "y" ]]; then
    install_binaries
else
    if [[ "$OS_ID" == "arch" ]]; then
        install_arch_choice_tools
    elif [[ "$OS_ID" == "ubuntu" ]] || [[ "$OS_ID" == "debian" ]]; then
        install_apt
    else
        log "WARN" "Unsupported OS for package manager: $OS_ID. Falling back to binary installation."
        install_binaries
    fi
fi

log "INFO" "Installation completed."
