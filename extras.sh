#!/bin/bash

set -e
set -u
set -o pipefail

source "$(dirname "$0")/common.sh"

trap 'cleanup ${LINENO} $?' EXIT

# OS Detection is inherited from common.sh

# Detect if running as root
if [ "$EUID" -eq 0 ]; then
    ROOT_MODE=true
    HOME="/root"
    log "INFO" "Running in root mode. Home directory set to /root"
else
    ROOT_MODE=false
fi
export ROOT_MODE


log "INFO" "Detected OS: $OS_ID"
# Collect all user inputs at the start
if [ "$ROOT_MODE" = false ]; then
    if [ -z "${HAS_SUDO:-}" ]; then
        read -p "Do you have sudo access? [y/n] " HAS_SUDO
    fi
else
    HAS_SUDO="y"
fi

if [[ "$IS_ARCH" == "true" ]]; then
    if [[ $HAS_SUDO = y ]]; then
        show_progress "Installing extra tools via $AUR_HELPER"
        "$AUR_HELPER" -S --needed --noconfirm hdf5 perl-image-exiftool ffmpeg imagemagick ghostscript playerctl
    
        # Wayland specific: Niri + DMS
        WAYLAND_PACKAGES=(
            xwayland-satellite xdg-desktop-portal-gnome xdg-desktop-portal-gtk
            ghostty dms-shell matugen-bin cava qt6-multimedia-ffmpeg
            wlr-randr niri iio-niri
        )
        "$AUR_HELPER" -S --needed --noconfirm "${WAYLAND_PACKAGES[@]}"
        systemctl --user add-wants niri.service dms
        mkdir -p ~/.config/niri/dms
        touch ~/.config/niri/dms/{colors,layout,alttab,binds}.kdl
        finish_progress

        # GUIs
        PACKAGES=()
        if gum confirm "Install Brave?"; then
            PACKAGES+=(brave-bin)
        fi
        if gum confirm "Install Chrome?"; then
            PACKAGES+=(google-chrome-stable)
        fi
        if gum confirm "Install Cursor?"; then
            PACKAGES+=(cursor-bin)
        fi
        if gum confirm "Install Antigravity?"; then
            PACKAGES+=(antigravity)
        fi
        if gum confirm "Install Spotify?"; then
            PACKAGES+=(spotify)
        fi
        if gum confirm "Install Discord?"; then
            PACKAGES+=(discord)
        fi
        if gum confirm "Install LibreOffice?"; then
            PACKAGES+=(libreoffice-fresh)
        fi
        if gum confirm "Install Obsidian?"; then
            PACKAGES+=(obsidian)
        fi
        if [ ${#PACKAGES[@]} -gt 0 ]; then
            "$AUR_HELPER" -S --needed --noconfirm "${PACKAGES[@]}"
        fi
    fi

elif [[ "$IS_DEBIAN" == "true" ]]; then

    if [[ $HAS_SUDO = y ]]; then
        # FFMPEG
        show_progress "Installing FFMPEG and related tools"
        run_command apt-get install libhdf5-dev exiftool ffmpeg -y
        finish_progress
        # ImageMagick and Ghostscript
        show_progress "Installing ImageMagick and Ghostscript"
        run_command apt-get install imagemagick ghostscript -y
        finish_progress

        # GUIs
        if gum confirm "Install Brave?"; then
            show_progress "Installing Brave Browser"
            if command -v snap >/dev/null 2>&1; then
                run_command snap install brave
            else
                log "WARN" "snap command not found. Cannot install Brave."
            fi
            finish_progress
        fi
        if gum confirm "Install Chrome?"; then
            show_progress "Installing Google Chrome"
            wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb -O /tmp/google-chrome-stable_current_amd64.deb
            run_command apt-get install /tmp/google-chrome-stable_current_amd64.deb -y
            rm -f /tmp/google-chrome-stable_current_amd64.deb
            finish_progress
        fi
        if gum confirm "Install Cursor?"; then
            show_progress "Installing Cursor"
            run_command mkdir -p /usr/share/keyrings
            curl -fsSL https://downloads.cursor.com/keys/anysphere.asc | \
              run_command gpg --dearmor --yes -o /usr/share/keyrings/anysphere.gpg
            cat <<EOF | run_command tee /etc/apt/sources.list.d/cursor.sources > /dev/null
### THIS FILE IS AUTOMATICALLY CONFIGURED ###
# You may comment out this entry, but any other modifications may be lost.
Types: deb
URIs: https://downloads.cursor.com/aptrepo
Suites: stable
Components: main
Architectures: amd64,arm64
Signed-By: /usr/share/keyrings/anysphere.gpg
EOF
            run_command apt-get update
            run_command apt-get install cursor -y
            finish_progress
        fi
        if gum confirm "Install Antigravity?"; then
            show_progress "Installing Antigravity"
            run_command mkdir -p /etc/apt/keyrings
            curl -fsSL https://us-central1-apt.pkg.dev/doc/repo-signing-key.gpg | \
              run_command gpg --dearmor --yes -o /etc/apt/keyrings/antigravity-repo-key.gpg
            echo "deb [signed-by=/etc/apt/keyrings/antigravity-repo-key.gpg] https://us-central1-apt.pkg.dev/projects/antigravity-auto-updater-dev/ antigravity-debian main" | \
              run_command tee /etc/apt/sources.list.d/antigravity.list > /dev/null
            run_command apt-get update
            run_command apt-get install antigravity -y
            finish_progress
        fi
        if gum confirm "Install Spotify?"; then
            show_progress "Installing Spotify"
            if command -v snap >/dev/null 2>&1; then
                run_command snap install spotify
            else
                log "WARN" "snap command not found. Cannot install Spotify."
            fi
            finish_progress
        fi
        if gum confirm "Install Discord?"; then
            show_progress "Installing Discord"
            if command -v snap >/dev/null 2>&1; then
                run_command snap install discord
            else
                log "WARN" "snap command not found. Cannot install Discord."
            fi
            finish_progress
        fi
        if gum confirm "Install LibreOffice?"; then
            show_progress "Installing LibreOffice"
            run_command apt-get install libreoffice -y
            finish_progress
        fi
        if gum confirm "Install Obsidian?"; then
            show_progress "Installing Obsidian"
            if command -v snap >/dev/null 2>&1; then
                run_command snap install obsidian --classic
            else
                log "WARN" "snap command not found. Cannot install Obsidian."
            fi
            finish_progress
        fi
    fi
fi
