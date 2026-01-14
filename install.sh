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


log "INFO" "Creating local bin directory"
mkdir -p "$HOME/.local/bin"
if [ ! -w "$HOME/.local/bin" ]; then
    log "ERROR" "Cannot write to $HOME/.local/bin"
    exit 1
fi
export PATH="$HOME/.local/bin:$PATH"

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



# -----------------------------------------------------------------------------
# Main Execution
# -----------------------------------------------------------------------------

main() {
    log "INFO" "Starting main execution..."
    
    # Custom Scripts (Always install these)


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

    # Custom Scripts (Always install these after stow is installed)
    stow_custom_scripts

    log "INFO" "Installation completed."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
