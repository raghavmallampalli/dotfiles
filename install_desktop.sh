#!/bin/bash

# install_desktop.sh - the niri + DankMaterialShell desktop and apps on Fedora (regular, dnf).
#
# Run as your own user (it uses sudo), after a Fedora "Minimal Install". Safe to re-run. Then
# run install_cli.sh and setup.sh. Steps that can't be automated are printed at the end.
#
# Package sources, in order of preference: Fedora repos, vendor repos / the DMS devs' COPRs,
# community COPRs / RPM Fusion, direct downloads. No Flatpak.

set -e
set -u
set -o pipefail

source "$(dirname "$0")/common.sh"

trap 'cleanup ${LINENO} $?' EXIT

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
DOWNLOAD_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/install_desktop"
MEDIA_UUID="00DD-836F"
MEDIA_MOUNT="/mnt/media-server"
ROOT_MODE=false
export ROOT_MODE

if [ "$IS_FEDORA" != "true" ]; then
    log "ERROR" "install_desktop.sh is for Fedora. Detected: $OS_ID"
    exit 1
fi
if [ "$IS_ATOMIC" = "true" ]; then
    log "ERROR" "This is an image-based (atomic) system; packages must be layered or built into the image instead."
    exit 1
fi
if [ "$EUID" -eq 0 ]; then
    log "ERROR" "Run as your own user, not root (it sets up your groups and user services)."
    exit 1
fi

FEDORA_VERSION="$(rpm -E %fedora)"
MANUAL_STEPS=()

# -----------------------------------------------------------------------------
# Package lists
# -----------------------------------------------------------------------------

# niri, DMS and everything the session needs
DESKTOP_PACKAGES=(
    niri quickshell dms dms-greeter greetd matugen dgop danksearch cliphist xwayland-satellite
    xdg-desktop-portal-gnome xdg-desktop-portal-gtk xdg-user-dirs xdg-utils
    gnome-keyring adw-gtk3-theme qt6ct qt6-qtmultimedia brightnessctl playerctl cava
    wl-clipboard wl-mirror wlr-randr kanshi python3-pyqt6
    pipewire wireplumber pipewire-pulseaudio pavucontrol
    bluez NetworkManager NetworkManager-wifi NetworkManager-openconnect
    power-profiles-daemon intel-lpmd fwupd
    mesa-dri-drivers mesa-vulkan-drivers vulkan-tools libva-utils intel-media-driver igt-gpu-tools
    gvfs gvfs-mtp udiskie ffmpegthumbnailer fuse fuse-libs
    snapper btrfs-progs btrfs-assistant libdnf5-plugin-actions cronie
    cups hplip sane-backends
    google-noto-sans-fonts google-noto-serif-fonts google-noto-sans-cjk-fonts
    google-noto-color-emoji-fonts liberation-fonts dejavu-sans-mono-fonts
)

# Command-line media tools (ffmpeg itself is swapped for RPM Fusion's full build below)
MEDIA_PACKAGES=(ImageMagick ghostscript perl-Image-ExifTool)

APP_PACKAGES=(
    brave-browser code ghostty claude-desktop-unofficial
    nautilus libreoffice inkscape mpv simple-scan copyq steam
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    tailscale
)

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

# Install packages, skipping any that aren't available, then report the missing ones
dnf_install() {
    run_command dnf install -y --skip-unavailable "$@" || log "WARN" "dnf reported errors installing: $*"
    local missing=()
    local pkg
    for pkg in "$@"; do
        [[ "$pkg" == *"://"* ]] && continue   # rpm URLs: dnf's own output covers these
        rpm -q --whatprovides "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        log "WARN" "Not installed (unavailable or failed): ${missing[*]}"
    fi
}

setup_repos() {
    log "INFO" "Updating the system and setting up repositories (Fedora $FEDORA_VERSION)"
    run_command dnf upgrade -y --refresh
    # copr and config-manager commands
    run_command dnf install -y dnf5-plugins

    # RPM Fusion: full ffmpeg, Intel video decoding, Steam
    if ! rpm -q rpmfusion-free-release rpmfusion-nonfree-release >/dev/null 2>&1; then
        run_command dnf install -y \
            "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VERSION}.noarch.rpm" \
            "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VERSION}.noarch.rpm"
    fi

    # DMS devs' COPRs (stable, not -git): danklinux has quickshell, dms-greeter, matugen and
    # ghostty; dms has DMS itself
    run_command dnf copr enable -y avengemedia/danklinux
    run_command dnf copr enable -y avengemedia/dms

    # Vendor repos
    run_command dnf config-manager addrepo --overwrite --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
    run_command dnf config-manager addrepo --overwrite --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo
    run_command dnf config-manager addrepo --overwrite --from-repofile=https://pkgs.tailscale.com/stable/fedora/tailscale.repo
    # Unofficial Claude Desktop rpm, repackaged from Anthropic's .deb; swap for Anthropic's repo once it exists
    run_command rpm --import https://pkg.claude-desktop-debian.dev/KEY.gpg
    run_command dnf config-manager addrepo --overwrite --from-repofile=https://pkg.claude-desktop-debian.dev/rpm/claude-desktop-unofficial.repo

    if [ ! -f /etc/yum.repos.d/vscode.repo ]; then
        run_command rpm --import https://packages.microsoft.com/keys/microsoft.asc
        printf '%s\n' "[code]" "name=Visual Studio Code" "baseurl=https://packages.microsoft.com/yumrepos/vscode" \
            "enabled=1" "autorefresh=1" "type=rpm-md" "gpgcheck=1" "gpgkey=https://packages.microsoft.com/keys/microsoft.asc" |
            run_command tee /etc/yum.repos.d/vscode.repo >/dev/null
    fi
}

install_desktop_packages() {
    log "INFO" "Installing the desktop layer"
    dnf_install "${DESKTOP_PACKAGES[@]}"
    dnf_install "${MEDIA_PACKAGES[@]}"
    # Full-codec ffmpeg from RPM Fusion instead of Fedora's ffmpeg-free
    if rpm -q ffmpeg-free >/dev/null 2>&1; then
        run_command dnf swap -y ffmpeg-free ffmpeg --allowerasing || log "WARN" "Could not swap in RPM Fusion's ffmpeg."
    fi
    # Firmware for common laptop hardware (Wi-Fi, Bluetooth, sound)
    run_command dnf group install -y hardware-support || log "WARN" "Could not install the hardware-support group."
}

install_apps() {
    log "INFO" "Installing apps"
    dnf_install "${APP_PACKAGES[@]}"

    # The ChatGPT rpm sets up OpenAI's repo on install, so later updates come through dnf
    if ! rpm -q chatgpt >/dev/null 2>&1; then
        dnf_install https://persistent.oaistatic.com/codex-app-prod/linux/rpm/latest/chatgpt.x86_64.rpm
    fi

    install_wvkbd
    install_iio_niri
    install_rquickshare
    install_zotero
}

# On-screen keyboard (started by the niri config as wvkbd-mobintl). Not packaged for Fedora,
# so build it from source into ~/.local/bin.
install_wvkbd() {
    if command -v wvkbd-mobintl >/dev/null 2>&1; then
        return 0
    fi
    show_progress "Building wvkbd"
    dnf_install gcc make pkgconf-pkg-config git wayland-devel libxkbcommon-devel cairo-devel pango-devel scdoc
    rm -rf "$DOWNLOAD_DIR/wvkbd"
    mkdir -p "$DOWNLOAD_DIR"
    git clone --quiet --depth 1 https://github.com/jjsullivan5196/wvkbd "$DOWNLOAD_DIR/wvkbd"
    make -s -C "$DOWNLOAD_DIR/wvkbd" >>"$LOG_FILE" 2>&1
    make -s -C "$DOWNLOAD_DIR/wvkbd" install PREFIX="$HOME/.local" >>"$LOG_FILE" 2>&1
    finish_progress
}

# Screen auto-rotation for niri (started by the niri config). Not packaged for Fedora, so build
# it with cargo, which comes from mise (install_cli.sh). On a fresh install that runs after this
# script, so the build happens on a second run.
install_iio_niri() {
    if command -v iio-niri >/dev/null 2>&1; then
        return 0
    fi
    dnf_install iio-sensor-proxy dbus-devel gcc pkgconf-pkg-config
    if ! command -v cargo >/dev/null 2>&1; then
        MANUAL_STEPS+=("iio-niri (screen rotation): needs cargo from install_cli.sh. Re-run ./install_desktop.sh after it to build iio-niri.")
        return 0
    fi
    show_progress "Building iio-niri"
    cargo install --quiet --locked --git https://github.com/Zhaith-Izaliel/iio-niri >>"$LOG_FILE" 2>&1
    finish_progress
}

# Desktop-only tools installed by mise (so `mise up` updates them). Kept in a machine-local
# config, not the shared tool list that servers use; install_cli.sh's `mise install` picks it up.
setup_desktop_mise_tools() {
    local conf="$HOME/.config/mise/conf.d/desktop.toml"
    mkdir -p "$(dirname "$conf")"
    if [ ! -f "$conf" ]; then
        printf '%s\n' "# Desktop-only tools (written by install_desktop.sh; not in the dotfiles repo)" "[tools]" \
            '"github:AvengeMedia/dankcalendar" = "latest"   # Dank Calendar (dcal)' >"$conf"
    fi
    if command -v mise >/dev/null 2>&1; then
        MISE_YES=1 mise install >>"$LOG_FILE" 2>&1 || log "WARN" "mise install failed for desktop tools."
    fi
    # The autostart entry from the Arch package points at /usr/bin/dcal
    local autostart="$HOME/.config/autostart/com.danklinux.dankcalendar.desktop"
    if [ -f "$autostart" ]; then
        sed -i 's|^Exec=/usr/bin/dcal |Exec=dcal |' "$autostart"
    fi
}

# Quick Share (Android nearby sharing): rpm from the latest GitHub release
install_rquickshare() {
    if rpm -q r-quick-share >/dev/null 2>&1 || command -v rquickshare >/dev/null 2>&1; then
        return 0
    fi
    local url
    url="$(curl -fsSL https://api.github.com/repos/Martichou/rquickshare/releases/latest |
        grep -oE '"browser_download_url": *"[^"]+x86_64\.rpm"' | grep -v -i legacy | head -n 1 | cut -d '"' -f 4)" || true
    if [ -n "$url" ]; then
        dnf_install "$url"
    else
        MANUAL_STEPS+=("RQuickShare: no .rpm found in the latest release; get it from github.com/Martichou/rquickshare/releases.")
    fi
}

# Zotero: official tarball into ~/.local/opt. It updates itself, and isn't sandboxed.
install_zotero() {
    local dir="$HOME/.local/opt/Zotero_linux-x86_64"
    if [ -x "$dir/zotero" ]; then
        return 0
    fi
    show_progress "Installing Zotero"
    mkdir -p "$DOWNLOAD_DIR" "$HOME/.local/opt" "$HOME/.local/share/applications"
    curl -fsSL -o "$DOWNLOAD_DIR/zotero.tar" "https://www.zotero.org/download/client/dl?channel=release&platform=linux-x86_64"
    tar -xf "$DOWNLOAD_DIR/zotero.tar" -C "$HOME/.local/opt"
    (cd "$dir" && ./set_launcher_icon)
    # Zotero's own launcher finds the program via %k, which DMS's launcher doesn't fill in
    sed "s|^Exec=.*|Exec=$dir/zotero -url %U|" "$dir/zotero.desktop" >"$HOME/.local/share/applications/zotero.desktop"
    finish_progress
}

setup_services() {
    log "INFO" "Enabling services"
    run_command systemctl enable --now bluetooth.service || true
    run_command systemctl enable --now tailscaled.service || true
    # Lets the tray app (tailscale systray) control Tailscale without sudo
    run_command tailscale set --operator="$USER" || true
    run_command systemctl enable --now docker.service || true
    run_command systemctl enable --now crond.service || true
    run_command systemctl enable cups.service || true
    run_command usermod -aG docker "$USER"

    # Minimal installs boot to a text console; the greeter needs the graphical target
    run_command systemctl set-default graphical.target

    # Greeter: dms-greeter enable writes /etc/greetd/config.toml, disables other display
    # managers and enables greetd; sync shares your DMS theme with the login screen
    if command -v dms-greeter >/dev/null 2>&1; then
        dms-greeter enable || log "WARN" "dms-greeter enable failed; see https://danklinux.com/docs/dankgreeter/installation"
        dms-greeter sync || true
    fi

    # Start DMS with niri only
    systemctl --user add-wants niri.service dms.service || true
}

# Snapshots of / before and after every dnf transaction (undo with Btrfs Assistant or
# `snapper undochange`). Only if / is btrfs.
setup_snapper() {
    if [ "$(findmnt -n -o FSTYPE /)" != "btrfs" ]; then
        return 0
    fi
    if ! snapper list-configs 2>/dev/null | grep -q "^root "; then
        run_command snapper -c root create-config /
        run_command snapper -c root set-config TIMELINE_CREATE=no NUMBER_LIMIT=10 NUMBER_LIMIT_IMPORTANT=5 \
            ALLOW_USERS="$USER" SYNC_ACL=yes
    fi
    run_command systemctl enable --now snapper-cleanup.timer || true
    run_command install -D -m 644 "$REPO_ROOT/system/dnf/snapper.actions" /etc/dnf/libdnf5-plugins/actions.d/snapper.actions
}

# Hibernation: point the kernel at the swap partition and add resume support to the initramfs.
# zram swap can't hold a hibernation image, so this needs a swap partition in /etc/fstab.
# Secure Boot must be off (Fedora blocks hibernation under it).
setup_hibernation() {
    local swap_dev swap_uuid
    swap_dev="$(awk '$3 == "swap" { print $1; exit }' /etc/fstab)"
    if [ -z "$swap_dev" ]; then
        MANUAL_STEPS+=("Hibernation: no swap partition in /etc/fstab, so it's not set up.")
        return 0
    fi
    if grep -q "resume=" /proc/cmdline; then
        return 0
    fi
    swap_uuid="${swap_dev#UUID=}"
    run_command grubby --update-kernel=ALL --args="resume=UUID=$swap_uuid"
    echo 'add_dracutmodules+=" resume "' | run_command tee /etc/dracut.conf.d/resume.conf >/dev/null
    run_command dracut -f --regenerate-all
    log "INFO" "Hibernation set up (takes effect after a reboot)."
}

# Weekly `mise self-update && mise up` (unit files are dotfiles, linked by setup.sh)
setup_update_timer() {
    if [ -f "$HOME/.config/systemd/user/mise-update.timer" ]; then
        systemctl --user daemon-reload
        systemctl --user enable --now mise-update.timer || true
    else
        MANUAL_STEPS+=("After setup.sh has linked the dotfiles: systemctl --user enable --now mise-update.timer")
    fi
}

# Media drive for the compose stack. exFAT has no SELinux labels, so give the whole mount
# the label containers are allowed to use.
setup_media_drive() {
    run_command mkdir -p "$MEDIA_MOUNT"
    if ! grep -q "$MEDIA_UUID" /etc/fstab; then
        echo "UUID=$MEDIA_UUID $MEDIA_MOUNT exfat defaults,users,uid=$(id -u),gid=$(id -g),umask=0022,nofail,noauto,context=system_u:object_r:container_file_t:s0 0 0" |
            run_command tee -a /etc/fstab >/dev/null
        run_command systemctl daemon-reload
        log "INFO" "Added the media drive to /etc/fstab"
    fi
    # Docker CE on Fedora doesn't enforce SELinux labels, so bind mounts from $HOME work as-is
    MANUAL_STEPS+=("Media server: pull the images first (cd ~/src/compose-files && docker compose pull), then: systemctl --user enable --now media-server.service")
}

report() {
    echo ""
    echo "==================================== NEXT ====================================="
    log "INFO" "Desktop installed. Next: ./install_cli.sh --sudo-access yes, then ./setup.sh, then reboot."
    local step
    for step in "${MANUAL_STEPS[@]}"; do
        log "WARN" "Manual: $step"
    done
    echo "================================================================================"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
    log "INFO" "Starting desktop installation (repo: $REPO_ROOT)"
    setup_repos
    install_desktop_packages
    install_apps
    setup_desktop_mise_tools
    setup_services
    setup_snapper
    setup_hibernation
    setup_update_timer
    setup_media_drive
    report
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
