#!/bin/bash

set -e
set -u
set -o pipefail

source "$(dirname "$0")/common.sh"

trap 'cleanup ${LINENO} $?' EXIT

# Parse command line arguments
# Parse command line arguments
SET_LOCAL_TIME=""
GH_LOGIN=""
SET_ZSH_DEFAULT=""
COPY_TMUX_CONFIG=""

# Function to show help
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -t, --local-time <y/n>         Set hardware clock to local time?"
    echo "  -g, --github-login <y/n>       Would you like to login to GitHub?"
    echo "  -z, --zsh-default <y/n>        Set zsh as default shell?"
    echo "  -c, --tmux-config <y/n>        Copy tmux configuration?"
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
                local-time)
                    SET_LOCAL_TIME="${!OPTIND}"
                    OPTIND=$((OPTIND + 1))
                    ;;
                github-login)
                    GH_LOGIN="${!OPTIND}"
                    OPTIND=$((OPTIND + 1))
                    ;;
                zsh-default)
                    SET_ZSH_DEFAULT="${!OPTIND}"
                    OPTIND=$((OPTIND + 1))
                    ;;
                tmux-config)
                    COPY_TMUX_CONFIG="${!OPTIND}"
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
        t)
            SET_LOCAL_TIME="$OPTARG"
            ;;
        g)
            GH_LOGIN="$OPTARG"
            ;;
        z)
            SET_ZSH_DEFAULT="$OPTARG"
            ;;
        c)
            COPY_TMUX_CONFIG="$OPTARG"
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
log "INFO" "Starting setup..."

# Backup existing configurations before starting
backup_configs

# Collect all user inputs at the start
# Check if we can set local time (not WSL)
if ! is_wsl; then
    if [ -z "$SET_LOCAL_TIME" ]; then
        read -p "Set hardware clock to local time? [y/n] " SET_LOCAL_TIME
    fi
else
    SET_LOCAL_TIME="n"
fi

# This will work even if gh is not installed, will just print the not logged in message
log "INFO" "Currently logged in GitHub accounts:"
gh auth status 2>/dev/null || echo "Not logged in to any GitHub accounts"
if [ -z "$GH_LOGIN" ]; then
    read -p "Would you like to login to GitHub? [y/n] " GH_LOGIN
fi

# Ask if zsh should be set as default shell
if [ -z "$SET_ZSH_DEFAULT" ]; then
    read -p "Set zsh as default shell? [y/n] " SET_ZSH_DEFAULT
    SET_ZSH_DEFAULT=${SET_ZSH_DEFAULT:-n}
fi

# Ask if tmux configuration should be copied
if [ -z "$COPY_TMUX_CONFIG" ]; then
    read -p "Copy tmux configuration? Not recommended, lot of defaults changed. [y/n] " COPY_TMUX_CONFIG
    COPY_TMUX_CONFIG=${COPY_TMUX_CONFIG:-n}
fi

######################################### SSH #####################################################

# SSH key generation and git setup
if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
    show_progress "Generating SSH key"
    mkdir -p "$HOME/.ssh"
    ssh-keygen -q -t ed25519 -C "$(whoami)@$(hostname)" -f "$HOME/.ssh/id_ed25519" -N ""
    eval "$(ssh-agent -s)" >/dev/null 2>&1
    ssh-add -q "$HOME/.ssh/id_ed25519"
    finish_progress
fi

######################################### BASIC CONFIG ##########################################

# Fixes time problems if Windows is installed on your PC alongside Ubuntu
if is_wsl; then
    log "INFO" "Cannot access timedatectl on WSL."
else
    if [[ $SET_LOCAL_TIME = y ]]; then
        show_progress "Setting hardware clock"
        execute timedatectl set-local-rtc 1 --adjust-system-clock
        finish_progress
    fi
fi

if [ -x "$(command -v gh)" ] && [[ $GH_LOGIN = y ]]; then
    gh auth login
elif ! [ -x "$(command -v gh)" ]; then
    log "WARN" "Github CLI not installed. Manually add key in $HOME/.ssh/id_ed25519.pub to github.com"
    log "INFO" "See https://docs.github.com/en/authentication/connecting-to-github-with-ssh/adding-a-new-ssh-key-to-your-github-account"
fi

########################################### DOT FILES ############################################

show_progress "Stowing dotfiles"
# Ensure stow is installed (should be from install.sh)
if command -v stow >/dev/null 2>&1; then
    # We assume the script is run from the repo root or one level deep. 
    # Best to be absolute or relative to script location.
    REPO_ROOT="$(dirname "$(readlink -f "$0")")"
    
    # Pre-stow cleanup to prevent conflicts
    for pkg in zsh tmux nvim yazi niri starship; do
        pre_stow_cleanup "$REPO_ROOT/dotfiles/$pkg" "$HOME"
    done
    
    # Execute stow
    # -d sets the directory to look for packages (relative to current or absolute)
    # -t sets the target directory (Home)
    stow -d "$REPO_ROOT/dotfiles" -t "$HOME" zsh tmux nvim yazi niri starship
    
    finish_progress
else
     log "ERROR" "Stow is not installed. Please run install.sh first."
     finish_progress 1
     exit 1
fi

########################################### ENVIRONMENT ###########################################

if [ -x "$(command -v zsh)"  ]; then
    show_progress "Configuring ZSH"

    # Create cache and state directories for XDG compliance
    mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
    mkdir -p "${XDG_STATE_HOME:-$HOME/.local/state}/zsh"

    if [ -d "$HOME/.oh-my-zsh" ]; then
        log "INFO" "Oh-My-Zsh already installed. Removing."
        execute rm -rf "$HOME/.oh-my-zsh"
    fi
    
    log "INFO" "Setting up Oh-My-Zsh"
    KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    log "INFO" "Installed Oh-My-Zsh."
    
    # Change default shell to zsh
    if [ "$SHELL" != "$(which zsh)" ] && [[ $SET_ZSH_DEFAULT = y ]]; then
        log "INFO" "Changing default shell to zsh"
        if [ "$ROOT_MODE" != "true" ]; then
            run_command chsh -s "$(which zsh)" "$(whoami)"
            log "INFO" "Shell changed to zsh. Changes will take effect after logout."
        else
            log "WARN" "Adding zsh auto-start to bashrc for root users."
            # Add zsh auto-start to bashrc for root users
            if [ -f "$HOME/.bashrc" ]; then
                # Check if the configuration is already present
                if ! grep -q "ZSH_STARTED" "$HOME/.bashrc"; then
                    echo "" >> "$HOME/.bashrc"
                    echo "# Auto-start zsh for root users (safer than chsh)" >> "$HOME/.bashrc"
                    echo 'if [ -t 1 ] && [ "$SHELL" != "$(which zsh)" ] && [ -z "$ZSH_STARTED" ]; then' >> "$HOME/.bashrc"
                    echo '    export ZSH_STARTED=1' >> "$HOME/.bashrc"
                    echo '    exec zsh' >> "$HOME/.bashrc"
                    echo 'fi' >> "$HOME/.bashrc"
                    log "INFO" "Added zsh auto-start configuration to $HOME/.bashrc"
                else
                    log "INFO" "Zsh auto-start configuration already present in $HOME/.bashrc"
                fi
            else
                log "WARN" "No .bashrc found for root user"
            fi
        fi


    fi
    if [ -f "/usr/bin/zsh" ]; then
        show_progress "Installing ZSH plugins"
        if [ ! -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions" ]; then
            git clone --quiet https://github.com/zsh-users/zsh-autosuggestions "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions" > /dev/null
        fi
        finish_progress
    fi

fi

# --- tmux plugin manager (TPM) + plugins -------------------------------------
# Plugins live under ~/.config/tmux/plugins, which is git-ignored in the tmux
# package, so a fresh checkout has neither TPM nor any plugins. Bootstrap both
# here, after stow has linked ~/.config/tmux.
if [ -x "$(command -v tmux)" ]; then
    TMUX_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf"
    TMUX_PLUGINS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/tmux/plugins"
    TPM_DIR="$TMUX_PLUGINS_DIR/tpm"

    # Check for the actual tpm executable, not just the directory. A partial or
    # empty checkout (e.g. a broken git husk left behind by an interrupted
    # setup) would otherwise be treated as "installed" and silently skipped,
    # leaving TPM unloaded and prefix+I unbound.
    if [ ! -x "$TPM_DIR/tpm" ]; then
        log "INFO" "Installing TPM (tmux plugin manager)..."
        rm -rf "$TPM_DIR"
        mkdir -p "$TMUX_PLUGINS_DIR"
        git clone --quiet https://github.com/tmux-plugins/tpm "$TPM_DIR"
    else
        log "INFO" "TPM already installed."
    fi

    # Install every plugin listed in tmux.conf non-interactively so the setup is
    # complete out of the box, without the user having to press prefix+I on the
    # first launch. TPM reads the plugin list from a running server that has
    # sourced the config, so drive a throwaway detached server on its own socket.
    if [ -x "$TPM_DIR/tpm" ] && [ -f "$TMUX_CONF" ]; then
        log "INFO" "Installing tmux plugins..."
        _tpm_sock="tpm-setup-$$"
        TERM="${TERM:-xterm-256color}" tmux -L "$_tpm_sock" new-session -d -x 200 -y 50 2>/dev/null || true
        tmux -L "$_tpm_sock" source-file "$TMUX_CONF" 2>/dev/null || true
        tmux -L "$_tpm_sock" run-shell "$TPM_DIR/bindings/install_plugins" 2>/dev/null || true
        tmux -L "$_tpm_sock" kill-server 2>/dev/null || true

        installed=$(find "$TMUX_PLUGINS_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
        log "INFO" "tmux plugins present: $installed"

        # If a tmux server is already running, reload the config so the freshly
        # installed plugins take effect immediately instead of only on next launch.
        if tmux has-session 2>/dev/null; then
            tmux source-file "$TMUX_CONF" 2>/dev/null || true
            log "INFO" "Reloaded config into the running tmux session."
        fi
    fi
fi

# bat config
if [ -x "$(command -v bat)" ]; then
    mkdir -p "$(bat --config-dir)/themes"
else
    log "WARN" "bat command not found, skipping bat configuration"
fi

if ! is_wsl; then
    log "INFO" "Mount windows partitions at startup using 'sudo fdisk -l' and by editing /etc/fstab"
fi

log "INFO" "Setup completed. Restart your shell."

if [[ $COPY_TMUX_CONFIG = y ]]; then
    log "INFO" "tmux plugins installed automatically. To manage them later: prefix+I (install), prefix+U (update), prefix+alt+u (uninstall unused)."
fi

######## 'SYSTEM' PYTHON #############
uv run --with numpy \
--with pandas \
--with scikit-learn \
--with ipython \
--with plotly \
--with catppuccin \
ipython profile create

# Configure catppuccin theme for ipython (IPython 9.0+)
IPYTHON_CONFIG="$HOME/.ipython/profile_default/ipython_config.py"
cat << 'EOF' >> "$IPYTHON_CONFIG"

from IPython.utils.PyColorize import linux_theme, theme_table
from copy import deepcopy

catppuccin_theme = "catppuccin-mocha"
theme = deepcopy(linux_theme)
theme.base = catppuccin_theme
theme_table[catppuccin_theme] = theme

c.TerminalInteractiveShell.true_color = True
c.TerminalInteractiveShell.colors = catppuccin_theme
EOF
