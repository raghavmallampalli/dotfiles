#!/bin/bash

set -e
set -u
set -o pipefail

source "$(dirname "$0")/common.sh"

trap 'cleanup ${LINENO} $?' EXIT

log "INFO" "Proceed if you have run cli.sh (and restarted shell), changed directory to the parent folder of this script and gone through it. Ctrl+C and do so first if not. [ENTER] to continue."
read dump

# Detect if running as root
if [ "$EUID" -eq 0 ]; then
    ROOT_MODE=true
    HOME="/root"
    log "INFO" "Running in root mode. Home directory set to /root"
else
    ROOT_MODE=false
fi
export ROOT_MODE

# OS Detection
OS_ID="unknown"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID=$ID
fi

# Gather all user input at the beginning using gum
install_nvm=n
if gum confirm "Install nvm?"; then
    install_nvm=y
fi

install_rust=n
if gum confirm "Install Rust?"; then
    install_rust=y
fi

install_uv=n
if gum confirm "Install uv?"; then
    install_uv=y
fi

install_docker=n
if gum confirm "Install Docker Engine?"; then
    install_docker=y
fi

# NVM (node version manager) installation
if [[ $install_nvm = y ]]; then
    show_progress "Installing NVM"
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
    finish_progress
fi

# Rust installation
if [[ $install_rust = y ]]; then
    show_progress "Installing Rust"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    finish_progress
fi

# UV installation
if [[ $install_uv = y ]]; then
    show_progress "Installing UV"
    curl -LsSf https://astral.sh/uv/install.sh | sh
    echo 'eval "$(uv generate-shell-completion zsh)"' >>"$HOME/.zshrc"
    finish_progress
fi

# Docker installation
if [[ $install_docker = y ]]; then
    if is_wsl; then
        log "WARN" "Docker installation skipped - running in WSL environment"
    else
        show_progress "Installing Docker Engine"
        
        if [[ "$OS_ID" == "arch" ]]; then
            # Arch Linux installation via yay
            # Docker and docker-compose
            execute yay -S --needed --noconfirm docker docker-compose
            
            # Post-install steps
            log "INFO" "Enabling Docker service..."
            run_command systemctl enable --now docker.service
            
            log "INFO" "Adding user to docker group..."
            run_command usermod -aG docker "$USER"
            
        elif [[ "$OS_ID" == "ubuntu" ]] || [[ "$OS_ID" == "debian" ]]; then
            # Ubuntu installation (Official Docker Repo)
            
            # Add Docker's official GPG key
            run_command apt-get update
            run_command apt-get install ca-certificates curl -y
            run_command install -m 0755 -d /etc/apt/keyrings
            run_command curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
            run_command chmod a+r /etc/apt/keyrings/docker.asc

            # Add the repository to Apt sources
            echo \
              "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
              $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
              run_command tee /etc/apt/sources.list.d/docker.list > /dev/null
            run_command apt-get update

            # Download and install Docker Engine
            run_command apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
            
            # Post-install steps
            log "INFO" "Adding user to docker group..."
            run_command usermod -aG docker "$USER"
        else
            log "WARN" "Unsupported OS for Docker installation: $OS_ID"
        fi
        
        finish_progress
    fi
fi

log "INFO" "Installation complete."
