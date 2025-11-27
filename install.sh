#!/bin/bash

set -e
set -u
set -o pipefail

source "$(dirname "$0")/common.sh"

trap 'cleanup ${LINENO} $?' EXIT

# Parse command line arguments
HAS_SUDO=""
INSTALL_FROM_PACKAGES=""

# Function to show help
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -s, --sudo-access <y/n>        Do you have sudo access?"
    echo "  -p, --package-install <y/n>    Install tools from package repositories?"
    echo "  -h, --help                      Show this help message"
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
                package-install)
                    INSTALL_FROM_PACKAGES="${!OPTIND}"
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
        p)
            INSTALL_FROM_PACKAGES="$OPTARG"
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
log "INFO" "If it exits without completing install run 'sudo apt --fix-broken install'."

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
    if [ -z "$INSTALL_FROM_PACKAGES" ]; then
        log "INFO" "You have sudo access. You can install certain tools from package repositories (faster) or from git (more up to date)."
        read -p "Install tools from package repositories? [y/n] (y=packages, n=source) " INSTALL_FROM_PACKAGES
        INSTALL_FROM_PACKAGES=${INSTALL_FROM_PACKAGES:-y}
    fi
else
    log "INFO" "No sudo access or running in root mode. Installing tools from source (git)."
    INSTALL_FROM_PACKAGES="n"
fi

show_progress "Creating local bin directory"
mkdir -p "$HOME/.local/bin"
if [ ! -w "$HOME/.local/bin" ]; then
    log "ERROR" "Cannot write to $HOME/.local/bin"
    exit 1
fi
export PATH="$HOME/.local/bin:$PATH"
finish_progress

######################################### BASIC PROGRAMS ##########################################

if [[ $HAS_SUDO = y ]]; then
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
    run_command apt-get install fonts-powerline aria2 -y
    run_command apt-get install moreutils -y
    finish_progress
fi

if [[ $HAS_SUDO = y ]]; then
    show_progress "Installing ZSH"
    run_command apt-get install zsh -y
    finish_progress
fi

if [[ $HAS_SUDO = y ]]; then
    show_progress "Installing Vim"
    run_command apt-get install vim -y
    finish_progress

    show_progress "Installing TMUX and dependencies"
    run_command apt-get install libevent-dev ncurses-dev build-essential bison pkg-config -y
    run_command apt-get install tmux -y
    finish_progress
fi

##################################### COMMAND LINE UTILITIES ######################################
log "INFO" "Installing command line utilities..."

# UV: helper to install pip tools system wide
curl -LsSf https://astral.sh/uv/install.sh | sh
echo 'eval "$(uv generate-shell-completion zsh)"' >> "$HOME/.zshrc"

# FZF: fuzzy finder - https://github.com/junegunn/fzf
if ! command -v fzf >/dev/null 2>&1; then
    show_progress "Installing FZF"
    if [ ! -d "$HOME/.fzf" ]; then
        execute git clone --quiet --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf"
    fi
    # Install with all features and do not update shell configs
    execute "$HOME/.fzf/install" --all
    # Download git integration script
    wget https://raw.githubusercontent.com/junegunn/fzf-git.sh/main/fzf-git.sh -qO "$HOME/.fzf-git.sh"
    finish_progress
fi

# ZOXIDE: directory navigation tool - https://github.com/ajeetdsouza/zoxide
show_progress "Installing Zoxide"
run_command apt-get install zoxide -y
finish_progress

# BAT: better cat - https://github.com/sharkdp/bat
show_progress "Installing BAT"
if [[ $INSTALL_FROM_PACKAGES = y ]]; then
    run_command apt-get install bat -y
    mkdir -p "$HOME/.local/bin"
    ln -f /usr/bin/batcat "$HOME/.local/bin/bat"
else
    url=$(wget "https://api.github.com/repos/sharkdp/bat/releases/latest" -qO-| grep browser_download_url | grep "gnu" | grep "x86_64" | grep "linux" | head -n 1 | cut -d \" -f 4)
    wget "$url" -qO- | tar -xz -C /tmp/
    mv /tmp/bat*/bat "$HOME/.local/bin/"
fi
finish_progress

# FD: simple find clone - https://github.com/sharkdp/fd
show_progress "Installing FD"
if [[ $INSTALL_FROM_PACKAGES = y ]]; then
    run_command apt-get install fd-find -y
    ln -sf "$(which fdfind)" "$HOME/.local/bin/fd"
else
    url=$(wget "https://api.github.com/repos/sharkdp/fd/releases/latest" -qO-|grep browser_download_url | grep "gnu" | grep "x86_64" | grep "linux" | head -n 1 | cut -d \" -f 4)
    wget "$url" -qO- | tar -xz -C /tmp
    mv /tmp/fd*/fd "$HOME/.local/bin/"
fi
finish_progress

# RIPGREP: faster grep - https://github.com/BurntSushi/ripgrep
show_progress "Installing Ripgrep"
if [[ $INSTALL_FROM_PACKAGES = y ]]; then
    url=$(wget "https://api.github.com/repos/BurntSushi/ripgrep/releases/latest" -qO-| grep browser_download_url | grep "deb" | head -n 1 | cut -d \" -f 4)
    wget "$url" -qO /tmp/rg.deb
    run_command dpkg -i /tmp/rg.deb
    run_command apt-get install -f
else
    url=$(wget "https://api.github.com/repos/BurntSushi/ripgrep/releases/latest" -qO-| grep browser_download_url | grep "x86_64" | grep "linux" | head -n 1 | cut -d \" -f 4)
    wget "$url" -qO- | tar -xz -C /tmp/
    mv /tmp/ripgrep*/rg "$HOME/.local/bin/"
fi
finish_progress

# YAZI: command line file navigation - https://github.com/sxyazi/yazi
show_progress "Installing Yazi"
wget -q https://github.com/sxyazi/yazi/releases/latest/download/yazi-x86_64-unknown-linux-musl.zip -O /tmp/yazi.zip
unzip -oq /tmp/yazi.zip -d /tmp
mv /tmp/yazi-x86_64-unknown-linux-musl/yazi "$HOME/.local/bin/"
mv /tmp/yazi-x86_64-unknown-linux-musl/ya "$HOME/.local/bin/"
chmod +x "$HOME/.local/bin/yazi"
chmod +x "$HOME/.local/bin/ya"
finish_progress

# Install duckdb for yazi preview support
show_progress "Installing DuckDB"
curl -sSfL https://install.duckdb.org | sh
if [ -f "$HOME/.duckdb/bin/duckdb" ]; then
    ln -sf "$HOME/.duckdb/cli/latest/duckdb" "$HOME/.local/bin/duckdb" 2>/dev/null || true
fi
finish_progress

# Install rich-cli for yazi preview support
show_progress "Installing rich-cli"
if command -v uv >/dev/null 2>&1; then
    uv tool install rich-cli
else
    log "WARN" "uv not found, skipping rich-cli installation"
fi
finish_progress

# IMV: intelligent move script
show_progress "Installing IMV script"
if [[ $HAS_SUDO = y ]]; then
    # Install to ~/.local/bin if we have sudo access
    cp "./scripts/imv" "$HOME/.local/bin/"
    chmod +x "$HOME/.local/bin/imv"
    log "INFO" "IMV script installed to ~/.local/bin"
else
    # Keep in current directory if no sudo access
    cp "./scripts/imv" "$HOME/.local/bin/"
    chmod +x "$HOME/.local/bin/imv"
    log "INFO" "IMV script installed to $HOME/.local/bin/, will not be accessible in sudo."
fi
finish_progress

# DUF: disk usage finder - https://github.com/muesli/duf
if [[ $HAS_SUDO = y ]]; then
    show_progress "Installing DUF"
    run_command apt-get install duf -y
    finish_progress
fi

# WSLVIEW: wsl utilities - https://github.com/wslutilities/wslu
if is_wsl && [[ $HAS_SUDO = y ]]; then
    show_progress "Installing WSLU"
    run_command apt-get install wslu -y
    finish_progress
fi

log "INFO" "Package installation completed."
