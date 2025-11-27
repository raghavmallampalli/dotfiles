#!/bin/bash

set -e
set -u
set -o pipefail

source "$(dirname "$0")/common.sh"

trap 'cleanup ${LINENO} $?' EXIT

log "INFO"  "Proceed if you have run cli.sh (and restarted shell), changed directory to the parent folder of this script and gone through it. Ctrl+C and do so first if not. [ENTER] to continue."
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

# Gather all user input at the beginning
install_miniconda=n
read -p "Install Miniconda? [y/n] " install_miniconda
read -p "Install nvm? [y/n] " install_nvm
read -p "Install Julia? [y/n] " install_julia
read -p "Install R? [y/n]: " install_r
read -p "Install GNU octave? [y/n]: " install_octave
read -p "Install Docker? [y/n]: " install_docker

if [[ $install_miniconda = y ]]; then
    show_progress "Installing Miniconda"
    tempvar=${tempvar:-n}
    if [ -d "$HOME/miniconda3" ]; then
        read -p "miniconda3 installed in default location directory. delete/manually enter install location/quit [d/m/Ctrl+C]: " tempvar
        tempvar=${tempvar:-n}
        if [[ $tempvar = d ]]; then
            rm -rf "$HOME/miniconda3"
        elif [[ $tempvar = m ]]; then
            log "INFO" "Ensure that you enter a different location during installation."
        fi
    fi
    wget -q https://repo.continuum.io/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /tmp/miniconda.sh
    chmod +x /tmp/miniconda.sh
    bash /tmp/miniconda.sh
    "$HOME/miniconda3/bin/conda" init zsh
    finish_progress
fi

# NVM (node version manager) installation
if [[ $install_nvm = y ]]; then
    show_progress "Installing NVM"
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
    finish_progress
fi



if [[ $install_julia = y ]]; then
    show_progress "Installing Julia"
    curl -fsSL https://install.julialang.org | sh
    log "INFO" "To use Julia with Jupyter Notebook https://github.com/JuliaLang/IJulia.jl#quick-start"
    finish_progress
fi

if [[ $install_r = y ]]; then
    show_progress "Installing R"
    run_command apt-get install --no-install-recommends software-properties-common dirmngr -y
    run_command apt-get install libzmq3-dev libcurl4-openssl-dev libssl-dev jupyter-core jupyter-client -y
    wget -qO- https://cloud.r-project.org/bin/linux/ubuntu/marutter_pubkey.asc | run_command tee -a /etc/apt/trusted.gpg.d/cran_ubuntu_key.asc >> /dev/null
    run_command add-apt-repository "deb https://cloud.r-project.org/bin/linux/ubuntu $(lsb_release -cs)-cran40/" -y >> /dev/null
    run_command apt-get install --no-install-recommends r-base -y
    run_command add-apt-repository ppa:c2d4u.team/c2d4u4.0+ -y >> /dev/null
    show_progress "Installing RStudio"
    run_command apt-get install rstudio -y
    finish_progress
fi

if [[ $install_octave = y ]]; then
    run_command apt-get install octave -y
fi

# Docker installation (only on non-WSL systems)
if [[ $install_docker = y ]]; then
    if is_wsl; then
        log "WARN" "Docker Desktop installation skipped - running in WSL environment"
    else
        show_progress "Installing Docker Desktop"
        
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

        # Download and install Docker Desktop
        wget -O /tmp/docker-desktop-amd64.deb https://desktop.docker.com/linux/main/amd64/docker-desktop-amd64.deb
        run_command dpkg -i /tmp/docker-desktop-amd64.deb
        
        finish_progress
    fi
fi

log "INFO" "Installation complete."
