#!/bin/bash

set -e
set -u
set -o pipefail

source "$(dirname "$0")/common.sh"

trap 'cleanup ${LINENO} $?' EXIT

# Parse command line arguments
REPLACE_DOTFILES=""
LINK_DOTFILES=""
SET_LOCAL_TIME=""
GH_LOGIN=""
SET_ZSH_DEFAULT=""
COPY_TMUX_CONFIG=""

# Function to show help
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -r, --replace-dotfiles <y/n>   Replace dotfiles?"
    echo "  -l, --link <y/n>               Soft-link dotfiles? (only if replacing, default: hard link)"
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
                replace-dotfiles)
                    REPLACE_DOTFILES="${!OPTIND}"
                    OPTIND=$((OPTIND + 1))
                    ;;
                link)
                    LINK_DOTFILES="${!OPTIND}"
                    OPTIND=$((OPTIND + 1))
                    ;;
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
        r)
            REPLACE_DOTFILES="$OPTARG"
            ;;
        l)
            LINK_DOTFILES="$OPTARG"
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
if [ -z "$REPLACE_DOTFILES" ]; then
    read -p "Replace dotfiles? Read script to see which files will be replaced. [y/n] " REPLACE_DOTFILES
fi

if [[ $REPLACE_DOTFILES = y ]] && [ -z "$LINK_DOTFILES" ]; then
    log "INFO" "Dotfiles will be hard linked by default (most efficient), or soft linked if you prefer."
    log "WARN" "If you soft link, moving or deleting this repo folder will break the links."
    read -p "Soft-link dotfiles? [y/n] (n=hard link, y=soft link) " LINK_DOTFILES
    LINK_DOTFILES=${LINK_DOTFILES:-n}
fi

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

if [[ $REPLACE_DOTFILES = y ]]; then
    show_progress "Installing dotfiles"
    dotfiles=(
        ".aliases"
        ".env_vars"
        ".vimrc"
        ".p10k.zsh"
    )
    
    # Add tmux configuration only if user allows it
    if [[ $COPY_TMUX_CONFIG = y ]]; then
        dotfiles+=(".tmux.conf")
    fi

    for dotfile in "${dotfiles[@]}"; do
        install_dotfile "./dotfiles/$dotfile" "$HOME/$dotfile" "$LINK_DOTFILES"
    done

    finish_progress
fi
source "$HOME/.aliases"

########################################### ENVIRONMENT ###########################################

if [ -x "$(command -v zsh)"  ]; then
    show_progress "Configuring ZSH"
    execute backup_and_delete "$HOME/.zshrc"
    execute backup_and_delete "$HOME/.zshrc.common"
    install_dotfile "./dotfiles/.zshrc.common" "$HOME/.zshrc.common" "$LINK_DOTFILES"

    if [ -d "$HOME/.oh-my-zsh" ]; then
        log "INFO" "Oh-My-Zsh already installed. Removing."
        execute rm -rf "$HOME/.oh-my-zsh"
    fi
    
    log "INFO" "Setting up Oh-My-Zsh"
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
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
        if [ ! -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k" ]; then
            git clone --quiet --depth=1 https://github.com/romkatv/powerlevel10k.git "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k" > /dev/null
        fi
        if [ ! -d "${ZSH_CUSTOM:=$HOME/.oh-my-zsh/custom}/plugins/conda-zsh-completion" ]; then
            git clone --quiet https://github.com/conda-incubator/conda-zsh-completion.git "${ZSH_CUSTOM:=$HOME/.oh-my-zsh/custom}/plugins/conda-zsh-completion" > /dev/null
        fi
        if [ ! -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions" ]; then
            git clone --quiet https://github.com/zsh-users/zsh-autosuggestions "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions" > /dev/null
        fi
        sed -i "s|ZSH_THEME=.*|ZSH_THEME=\"powerlevel10k/powerlevel10k\"|" "$HOME/.zshrc"
        sed -i "s|plugins=.*|plugins=(git dotenv conda-zsh-completion zsh-autosuggestions zoxide fzf)|" "$HOME/.zshrc"
        sed -i "s|source \$ZSH/oh-my-zsh.sh.*|source \$ZSH/oh-my-zsh.sh\; autoload -U compinit \&\& compinit|" "$HOME/.zshrc"
        finish_progress
    fi

    echo "source \$HOME/.zshrc.common" | cat - "$HOME/.zshrc" > temp && mv temp "$HOME/.zshrc"

fi

if [ -d "$HOME/.tmux/plugins/tpm" ]; then
    # Already installed, but check if we need to install it?
    # Actually, install.sh installs tmux, but setup.sh configures it.
    # We should probably ensure TPM is there if tmux is there.
    :
else
    if [ -x "$(command -v tmux)" ]; then
        mkdir -p "$HOME/.tmux/plugins"
        git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
    fi
fi

# bat config
if [ -x "$(command -v bat)" ]; then
    mkdir -p "$(bat --config-dir)/themes"
    wget -P "$(bat --config-dir)/themes" https://github.com/catppuccin/bat/raw/main/themes/Catppuccin%20Mocha.tmTheme
    bat cache --build
else
    log "WARN" "bat command not found, skipping bat configuration"
fi


# Install yazi configuration files
show_progress "Installing yazi plugins"
if command -v ya >/dev/null 2>&1; then
    ya pkg add wylie102/duckdb || log "WARN" "Failed to install yazi duckdb plugin"
    ya pkg add AnirudhG07/rich-preview || log "WARN" "Failed to install yazi rich-preview plugin"
else
    log "WARN" "ya command not found, skipping plugin installation"
fi
finish_progress

show_progress "Installing yazi configuration files"
mkdir -p "$HOME/.config/yazi"
for yazi_file in ./dotfiles/yazi/*; do
    if [ -f "$yazi_file" ]; then
        install_dotfile "$yazi_file" "$HOME/.config/yazi/$(basename "$yazi_file")" "$LINK_DOTFILES"
    fi
done

finish_progress

if ! is_wsl; then
    log "INFO" "Mount windows partitions at startup using 'sudo fdisk -l' and by editing /etc/fstab"
fi

log "INFO" "Setup completed. Restart your shell."

if [[ $COPY_TMUX_CONFIG = y ]]; then
    log "WARN" "Press Ctrl+A I (capital I) on first run of tmux to install plugins."
fi

######## 'SYSTEM' PYTHON #############
uv run --with ipython ipython profile create

echo "Below code block, inserted into the ipython_config.py file will provide syntax highlighting for catppuccin theme."
cat << EOF
from IPython.utils.PyColorize import linux_theme, theme_table
from copy import deepcopy

theme = deepcopy(linux_theme)

# Choose catppuccin theme
catppuccin_theme = "catppuccin-mocha"
# catppuccin_theme = "catppuccin-macchiato"
# catppuccin_theme = "catppuccin-frappe"
# catppuccin_theme = "catppuccin-latte"

theme.base = catppuccin_theme
theme_table[catppuccin_theme] = theme
c = get_config()  #noqa`
c.TerminalInteractiveShell.true_color = True
c.TerminalInteractiveShell.colors = catppuccin_theme
EOF
# Fetch packages into cache for faster solve next time

py