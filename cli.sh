#!/bin/bash

set -e
set -u
set -o pipefail

source "$(dirname "$0")/common.sh"

trap 'cleanup ${LINENO} $?' EXIT

# Parse command line arguments
HAS_SUDO=""
REPLACE_DOTFILES=""
LINK_DOTFILES=""
SET_LOCAL_TIME=""
GH_LOGIN=""
INSTALL_FROM_PACKAGES=""
SET_ZSH_DEFAULT=""
COPY_TMUX_CONFIG=""

# Function to show help
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -s, --sudo-access <y/n>        Do you have sudo access?"
    echo "  -r, --replace-dotfiles <y/n>   Replace dotfiles?"
    echo "  -l, --link <y/n>               Link dotfiles? (only if replacing, default: hard link)"
    echo "  -t, --local-time <y/n>         Set hardware clock to local time?"
    echo "  -g, --github-login <y/n>       Would you like to login to GitHub?"
    echo "  -p, --package-install <y/n>    Install tools from package repositories?"
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
                sudo-access)
                    HAS_SUDO="${!OPTIND}"
                    OPTIND=$((OPTIND + 1))
                    ;;
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
                package-install)
                    INSTALL_FROM_PACKAGES="${!OPTIND}"
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
        s)
            HAS_SUDO="$OPTARG"
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
        p)
            INSTALL_FROM_PACKAGES="$OPTARG"
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
log "INFO" "Starting installation"
log "WARN" "Do not execute this file without reading it first and changing directory to the parent folder of this script."
log "INFO" "If it exits without completing install run 'sudo apt --fix-broken install'."

# Backup existing configurations before starting
backup_configs

# Collect all user inputs at the start
if [ "$ROOT_MODE" = false ]; then
    if [ -z "$HAS_SUDO" ]; then
        read -p "Do you have sudo access? [y/n] " HAS_SUDO
    fi
else
    HAS_SUDO="y"
fi

if [ -z "$REPLACE_DOTFILES" ]; then
    read -p "Replace dotfiles? Read script to see which files will be replaced. [y/n] " REPLACE_DOTFILES
fi

if [[ $REPLACE_DOTFILES = y ]] && [ -z "$LINK_DOTFILES" ]; then
    log "INFO" "Dotfiles will be hard linked by default (most efficient), or soft linked if you prefer to keep them up to date."
    log "WARN" "If you soft link, moving or deleting this repo folder will break the links."
    read -p "Link dotfiles? [y/n] (n=hard link, y=soft link) " LINK_DOTFILES
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

show_progress "Creating local bin directory"
mkdir -p "$HOME/.local/bin"
if [ ! -w "$HOME/.local/bin" ]; then
    log "ERROR" "Cannot write to $HOME/.local/bin"
    exit 1
fi
finish_progress

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

######################################### BASIC PROGRAMS ##########################################

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
    run_command apt-get install xclip jq autossh -y
    run_command apt-get install htop nvtop -y
    run_command apt-get install fonts-powerline aria2 -y
    run_command apt-get install moreutils -y
    finish_progress
    

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
    mkdir -p "$HOME/.config/espanso/match"
    
    # Add tmux configuration only if user allows it
    if [[ $COPY_TMUX_CONFIG = y ]]; then
        dotfiles+=(".tmux.conf")
    fi

    for dotfile in "${dotfiles[@]}"; do
        install_dotfile "./dotfiles/$dotfile" "$HOME/$dotfile" "$LINK_DOTFILES"
    done

    install_dotfile "./dotfiles/espanso_base.yml" "$HOME/.config/espanso/match/base.yml" "$LINK_DOTFILES"
    finish_progress
fi

########################################### ENVIRONMENT ###########################################
if [[ $HAS_SUDO = y ]]; then
    show_progress "Setting up ZSH environment"
    execute backup_and_delete "$HOME/.zshrc"
    rm -rf "$HOME/.z*"
    run_command apt-get install zsh -y
    finish_progress
fi

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
        sed -i "s|plugins=.*|plugins=(git dotenv conda-zsh-completion zsh-autosuggestions zoxide)|" "$HOME/.zshrc"
        sed -i "s|source \$ZSH/oh-my-zsh.sh.*|source \$ZSH/oh-my-zsh.sh\; autoload -U compinit \&\& compinit|" "$HOME/.zshrc"
        finish_progress
    fi

    echo "source \$HOME/.zshrc.common" | cat - "$HOME/.zshrc" > temp && mv temp "$HOME/.zshrc"

fi

if [[ $HAS_SUDO = y ]]; then
    show_progress "Installing Vim"
    run_command apt-get install vim -y
    finish_progress

    show_progress "Installing TMUX and dependencies"
    run_command apt-get install libevent-dev ncurses-dev build-essential bison pkg-config -y
    run_command apt-get install tmux -y
    if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
        rm -rf "$HOME/.tmux/plugins/tpm"
        mkdir -p "$HOME/.tmux/plugins"
        git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
    fi
    finish_progress
fi

##################################### COMMAND LINE UTILITIES ######################################
log "INFO" "Installing command line utilities..."

# FZF: fuzzy finder - https://github.coym/junegunn/fzf
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
    ln -sf /usr/bin/batcat "$HOME/.local/bin/bat"
else
    url=$(wget "https://api.github.com/repos/sharkdp/bat/releases/latest" -qO-| grep browser_download_url | grep "gnu" | grep "x86_64" | grep "linux" | head -n 1 | cut -d \" -f 4)
    wget "$url" -qO- | tar -xz -C /tmp/
    mv /tmp/bat*/bat "$HOME/.local/bin/"
fi
mkdir -p "$(bat --config-dir)/themes"
wget -P "$(bat --config-dir)/themes" https://github.com/catppuccin/bat/raw/main/themes/Catppuccin%20Mocha.tmTheme
bat cache --build
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
install_dotfile "./dotfiles/globalgitignore" "$HOME/.rgignore" "$LINK_DOTFILES"
finish_progress

# YAZI: command line file navigation - https://github.com/sxyazi/yazi
show_progress "Installing Yazi"
wget -q https://github.com/sxyazi/yazi/releases/latest/download/yazi-x86_64-unknown-linux-musl.zip -O /tmp/yazi.zip
unzip -q /tmp/yazi.zip -d /tmp
mv /tmp/yazi "$HOME/.local/bin/"
mv /tmp/yz "$HOME/.local/bin/"
chmod +x "$HOME/.local/bin/yazi"
chmod +x "$HOME/.local/bin/yz"
mkdir -p "$HOME/.config/yazi"
finish_progress

# Install duckdb for yazi preview support
show_progress "Installing DuckDB"
curl -sSfL https://install.duckdb.org | sh
if [ -f "$HOME/.duckdb/bin/duckdb" ]; then
    ln -sf "$HOME/.duckdb/bin/duckdb" "$HOME/.local/bin/duckdb" 2>/dev/null || true
fi
finish_progress

# Install rich-cli for yazi preview support
show_progress "Installing rich-cli"
if command -v uv >/dev/null 2>&1; then
    uv tool add rich-cli
else
    log "WARN" "uv not found, skipping rich-cli installation"
fi
finish_progress

# Install yazi duckdb plugin
show_progress "Installing yazi duckdb plugin"
if command -v yz >/dev/null 2>&1; then
    yz pack -a wylie102/duckdb || log "WARN" "Failed to install yazi duckdb plugin"
else
    log "WARN" "yz command not found, skipping plugin installation"
fi
finish_progress

# Install yazi configuration files
show_progress "Installing yazi configuration files"
for yazi_file in ./dotfiles/yazi/*; do
    if [ -f "$yazi_file" ]; then
        install_dotfile "$yazi_file" "$HOME/.config/yazi/$(basename "$yazi_file")" "$LINK_DOTFILES"
    fi
done
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

# ESPANSO: text expander - https://espanso.org/
if [[ $HAS_SUDO = y ]] && ! is_wsl; then
    show_progress "Installing Espanso"
    # Note: This uses the Wayland-compatible version.
    # For X11, the package name would be different.
    wget "https://github.com/espanso/espanso/releases/latest/download/espanso-debian-wayland-amd64.deb" -qO /tmp/espanso.deb
    run_command apt install /tmp/espanso.deb -y

    # Register espanso to start on boot
    # This needs to run as the user, not root
    if [ "$ROOT_MODE" = "true" ]; then
        log "WARN" "Skipping 'espanso register' in root mode. Run it manually as the target user."
    else
        /usr/bin/espanso register
    fi
    finish_progress
fi

# WSLVIEW: wsl utilities - https://github.com/wslutilities/wslu
if is_wsl && [[ $HAS_SUDO = y ]]; then
    show_progress "Installing WSLU"
    run_command apt-get install wslu -y
    finish_progress
fi

#####################################################################################

if ! is_wsl; then
    log "INFO" "Mount windows partitions at startup using 'sudo fdisk -l' and by editing /etc/fstab"
fi

log "INFO" "Installation completed. Restart and install other scripts."

if [[ $COPY_TMUX_CONFIG = y ]]; then
    log "WARN" "Press Ctrl+A I (capital I) on first run of tmux to install plugins."
fi
