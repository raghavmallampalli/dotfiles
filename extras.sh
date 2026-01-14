set -e
set -u
set -o pipefail

source "$(dirname "$0")/common.sh"

trap 'cleanup ${LINENO} $?' EXIT

# OS Detection
OS_ID="unknown"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID=$ID
fi

log "INFO" "Detected OS: $OS_ID"
# Collect all user inputs at the start
if [ "$ROOT_MODE" = false ]; then
    if [ -z "$HAS_SUDO" ]; then
        read -p "Do you have sudo access? [y/n] " HAS_SUDO
    fi
else
    HAS_SUDO="y"
fi

if [[ $OS_ID = "arch" ]]; then
    if [[ $HAS_SUDO = y ]]; then
        show_progress "Installing extra tools via yay"
        yay -S --needed --noconfirm hdf5 perl-image-exiftool ffmpeg imagemagick ghostscript playerctl
    
        # Wayland specific: Niri + DMS
        local WAYLAND_PACKAGES=(
            xwayland-satellite xdg-desktop-portal-gnome xdg-desktop-portal-gtk
            ghostty dms-shell-bin matugen cava qt6-multimedia-ffmpeg
            kanshi wlr-randr niri
        )
        yay -S --needed --noconfirm "${WAYLAND_PACKAGES[@]}"
        systemctl --user add-wants niri.service dms
        mkdir -p ~/.config/niri/dms
        touch ~/.config/niri/dms/{colors,layout,alttab,binds}.kdl
        finish_progress

        # GUIs
        local PACKAGES=()
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
            yay -S --needed --noconfirm "${PACKAGES[@]}"
        fi
    fi

elif [[ $OS_ID = "ubuntu" ]] || [[ $OS_ID = "debian" ]]; then

    if [[ $HAS_SUDO = y ]]; then
        # FFMPEG
        show_progress "Installing FFMPEG and related tools"
        run_command apt-get install libhdf5-dev exiftool ffmpeg -y
        finish_progress
        # ImageMagick and Ghostscript
        show_progress "Installing ImageMagick and Ghostscript"
        run_command apt-get install imagemagick ghostscript -y
        finish_progress
    fi
fi
