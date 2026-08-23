#!/bin/bash

set -e
set -u
set -o pipefail

source "$(dirname "$0")/common.sh"

trap 'cleanup ${LINENO} $?' EXIT

# Parse command line arguments
SUDO_ACCESS=""

# Function to show help
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -h, --help                     Show this help message"
    echo "  --sudo-access <yes/no>         Do you have sudo access? 'no' skips apt/pacman"
    echo "                                 entirely and installs only what's available as"
    echo "                                 portable binaries (Debian/Ubuntu only)."
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
        sudo-access)
            SUDO_ACCESS="${!OPTIND}"
            OPTIND=$((OPTIND + 1))
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

# Normalize --sudo-access to "yes"/"no" (or leave empty to prompt/decide later)
case "$SUDO_ACCESS" in
[yY]*) SUDO_ACCESS="yes" ;;
[nN]*) SUDO_ACCESS="no" ;;
"") ;;
*)
    echo "Invalid value for --sudo-access: $SUDO_ACCESS (expected yes/no)"
    show_help
    ;;
esac

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

# Resolve sudo access (only matters for the Debian/Ubuntu apt path; root always has
# full package-manager access so there's nothing to ask)
if [[ "$IS_DEBIAN" == "true" ]]; then
    if [ "$ROOT_MODE" = true ]; then
        SUDO_ACCESS="yes"
    elif [ -z "$SUDO_ACCESS" ]; then
        read -p "Do you have sudo access? [Y/n] " sudo_reply
        case "${sudo_reply:-y}" in
        [nN]*) SUDO_ACCESS="no" ;;
        *) SUDO_ACCESS="yes" ;;
        esac
    fi
    log "INFO" "Sudo access: $SUDO_ACCESS"
fi
export SUDO_ACCESS

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


    if [[ "$IS_ARCH" == "true" ]]; then
        log "INFO" "Installing bootstrap packages for Arch Linux..."

        show_progress "Updating system and installing prerequisites"
        # Basic tools needed to bootstrap the rest
        run_command pacman -Sy --needed --noconfirm git base-devel ca-certificates
        finish_progress
        
        install_aur_helper_if_needed
        install_tools_aur
        
    elif [[ "$IS_DEBIAN" == "true" ]]; then
        if [ "$SUDO_ACCESS" = "no" ]; then
            log "WARN" "No sudo access: skipping apt entirely. Only tools available as portable binaries will be installed."
            install_tools_binaries
        else
            # On Ubuntu, we start with minimal system setup, then use binaries for tools
            install_apt_always
            install_tools_binaries
        fi
    else
        log "WARN" "Unsupported OS for package manager: $OS_ID. Attempting binary installation for tools..."
        install_tools_binaries
    fi

    # Verify the union of tools all three install paths are expected to provide
    verify_master_tools

    # Custom Scripts (Always install these after stow is installed)
    stow_custom_scripts

    log "INFO" "Installation completed."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
