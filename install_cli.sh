#!/bin/bash

# install_cli.sh - shell, CLI, monitoring and dev tools. Meant for laptops and servers alike.
#
# Everything possible comes from mise (Python CLIs through uv, via mise's pipx backend) and
# lands in $HOME, so this works without sudo. With sudo, it also installs the handful of
# tools mise can't provide (zsh, ssh, ...) through apt, dnf or pacman. Either way it ends
# with a report of anything still missing.

set -e
set -u
set -o pipefail

source "$(dirname "$0")/common.sh"

trap 'cleanup ${LINENO} $?' EXIT

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
MISE_CONFIG_SRC="$REPO_ROOT/dotfiles/mise/.config/mise/config.toml"
MISE_CONFIG_DEST="$HOME/.config/mise/config.toml"
MISE_BIN="$HOME/.local/bin/mise"
MISE_SHIMS="${XDG_DATA_HOME:-$HOME/.local/share}/mise/shims"
# PATH as the user had it, before we add mise's shims. Used to spot other copies of tools.
ORIG_PATH="$PATH"

# Tools mise/uv can't provide. Format: "command:apt package:dnf package:pacman package"
SYSTEM_TOOLS=(
    "zsh:zsh:zsh:zsh"
    "git:git:git:git"
    "curl:curl:curl:curl"
    "wget:wget:wget:wget"
    "rsync:rsync:rsync:rsync"
    "ssh:openssh-client:openssh-clients:openssh"
    "zip:zip:zip:zip"
    "unzip:unzip:unzip:unzip"
    "autossh:autossh:autossh:autossh"
    "nvtop:nvtop:nvtop:nvtop"
)

# Commands the mise config is expected to provide (checked after install)
MISE_COMMANDS=(
    nvim fzf rg fd bat zoxide duf vivid yazi lazygit lazydocker starship gum gh jq duckdb
    tmux micro fastfetch rclone 7zz chezmoi btop
    uv node npm cargo rustc java cmake zig claude codex
    rich nvitop gpustat
)

SUDO_ACCESS=""

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -h, --help                     Show this help message"
    echo "  --sudo-access <yes/no>         Do you have sudo access? 'no' installs only into \$HOME"
    echo "                                 (mise + uv) and reports system tools that are missing."
    echo ""
    echo "If --sudo-access is not provided, the script will prompt."
    exit 0
}

while getopts ":-:" opt; do
    case $opt in
    -)
        case "${OPTARG}" in
        help) show_help ;;
        sudo-access)
            SUDO_ACCESS="${!OPTIND:-}"
            OPTIND=$((OPTIND + 1))
            ;;
        *)
            echo "Unknown option: --${OPTARG}"
            show_help
            ;;
        esac
        ;;
    h) show_help ;;
    \?)
        echo "Invalid option: -$OPTARG"
        show_help
        ;;
    esac
done

case "$SUDO_ACCESS" in
[yY]*) SUDO_ACCESS="yes" ;;
[nN]*) SUDO_ACCESS="no" ;;
"") ;;
*)
    echo "Invalid value for --sudo-access: $SUDO_ACCESS (expected yes/no)"
    show_help
    ;;
esac

if [ "$EUID" -eq 0 ]; then
    ROOT_MODE=true
    SUDO_ACCESS="yes"
else
    ROOT_MODE=false
fi
export ROOT_MODE

if [ -z "$SUDO_ACCESS" ]; then
    read -p "Do you have sudo access? [Y/n] " sudo_reply
    case "${sudo_reply:-y}" in
    [nN]*) SUDO_ACCESS="no" ;;
    *) SUDO_ACCESS="yes" ;;
    esac
fi
export SUDO_ACCESS

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

detect_pkg_manager() {
    if [ "$IS_ATOMIC" = "true" ]; then
        PKG_MGR="rpm-ostree"
    elif command -v apt-get >/dev/null 2>&1; then
        PKG_MGR="apt"
    elif command -v dnf >/dev/null 2>&1; then
        PKG_MGR="dnf"
    elif command -v pacman >/dev/null 2>&1; then
        PKG_MGR="pacman"
    else
        PKG_MGR="none"
    fi
    log "INFO" "Package manager: $PKG_MGR"
}

# Install whichever SYSTEM_TOOLS are missing, one package at a time so a single
# unavailable package (e.g. nvtop without Ubuntu's multiverse) doesn't stop the rest.
install_system_tools() {
    local missing=()
    local entry cmd apt_pkg dnf_pkg pacman_pkg
    for entry in "${SYSTEM_TOOLS[@]}"; do
        IFS=':' read -r cmd apt_pkg dnf_pkg pacman_pkg <<<"$entry"
        command -v "$cmd" >/dev/null 2>&1 && continue
        case "$PKG_MGR" in
        apt) missing+=("$apt_pkg") ;;
        dnf | rpm-ostree) missing+=("$dnf_pkg") ;;
        pacman) missing+=("$pacman_pkg") ;;
        esac
    done

    if [ ${#missing[@]} -eq 0 ]; then
        log "INFO" "System tools already present."
        return 0
    fi

    case "$PKG_MGR" in
    apt)
        run_command apt-get update || log "WARN" "apt-get update failed; trying to install anyway."
        for pkg in "${missing[@]}"; do
            run_command apt-get install -y "$pkg" || log "WARN" "Could not install $pkg via apt."
        done
        ;;
    dnf)
        for pkg in "${missing[@]}"; do
            run_command dnf install -y "$pkg" || log "WARN" "Could not install $pkg via dnf."
        done
        ;;
    pacman)
        # Fresh images (e.g. Docker) ship without a package database
        if [ -z "$(ls -A /var/lib/pacman/sync 2>/dev/null)" ]; then
            run_command pacman -Sy --noconfirm || log "WARN" "pacman -Sy failed."
        fi
        for pkg in "${missing[@]}"; do
            run_command pacman -S --needed --noconfirm "$pkg" || log "WARN" "Could not install $pkg via pacman."
        done
        ;;
    rpm-ostree)
        log "WARN" "Image-based system: not layering packages automatically. To add them: sudo rpm-ostree install ${missing[*]}"
        ;;
    none)
        log "WARN" "No supported package manager found. Install manually: ${missing[*]}"
        ;;
    esac
}

install_mise() {
    if [ -x "$MISE_BIN" ]; then
        log "INFO" "mise already installed at $MISE_BIN"
        return 0
    fi
    if command -v mise >/dev/null 2>&1; then
        MISE_BIN="$(command -v mise)"
        log "INFO" "Using existing mise at $MISE_BIN"
        return 0
    fi

    show_progress "Installing mise"
    mkdir -p "$HOME/.local/bin"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL https://mise.run | sh >>"$LOG_FILE" 2>&1
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- https://mise.run | sh >>"$LOG_FILE" 2>&1
    else
        log "ERROR" "Neither curl nor wget is available, so mise can't be downloaded."
        exit 1
    fi
    finish_progress
}

# Point mise's global config at the repo copy. setup.sh links the same file via chezmoi later,
# but mise needs it now to know what to install.
link_mise_config() {
    mkdir -p "$(dirname "$MISE_CONFIG_DEST")"
    if [ "$(readlink -f "$MISE_CONFIG_DEST" 2>/dev/null)" = "$(readlink -f "$MISE_CONFIG_SRC")" ]; then
        log "INFO" "mise config already linked."
        return 0
    fi
    backup_and_delete "$MISE_CONFIG_DEST"
    ln -s "$MISE_CONFIG_SRC" "$MISE_CONFIG_DEST"
    log "INFO" "Linked $MISE_CONFIG_DEST -> $MISE_CONFIG_SRC"
}

# Claude Code's own installer puts it in ~/.local/bin and keeps it updated. If that copy is
# here, leave it in charge on this machine by disabling mise's claude in a machine-local
# config (not in the repo). Fresh installs have no such copy and get mise's version.
# Delete the file below to switch this machine over to mise's claude.
keep_native_claude() {
    local local_conf="$HOME/.config/mise/conf.d/local.toml"
    if [ -x "$HOME/.local/bin/claude" ] && [ ! -e "$local_conf" ]; then
        mkdir -p "$(dirname "$local_conf")"
        printf '# Machine-local mise settings (not in the dotfiles repo)\n[settings]\ndisable_tools = ["claude"]\n' >"$local_conf"
        log "INFO" "Native Claude Code found in ~/.local/bin; disabled mise's claude in $local_conf"
    fi
}

# Most mise tools download from GitHub releases. Unauthenticated requests are limited to
# 60/hour (often shared on university/company IPs), so use a token when one is available.
setup_github_token() {
    if [ -n "${GITHUB_TOKEN:-}" ] || [ -n "${MISE_GITHUB_TOKEN:-}" ]; then
        return 0
    fi
    if command -v gh >/dev/null 2>&1 && gh auth token >/dev/null 2>&1; then
        MISE_GITHUB_TOKEN="$(gh auth token)"
        export MISE_GITHUB_TOKEN
        log "INFO" "Using the GitHub CLI's token for downloads."
    else
        log "INFO" "No GitHub token found. If downloads hit rate limits, rerun with GITHUB_TOKEN=<token>."
    fi
}

install_mise_tools() {
    export MISE_YES=1
    "$MISE_BIN" trust --quiet "$MISE_CONFIG_SRC" >/dev/null 2>&1 || true

    # uv first: the pipx: tools in the config are installed through it
    log "INFO" "Installing uv..."
    if ! "$MISE_BIN" install uv; then
        log "WARN" "uv failed to install; the pipx: tools will fall back to pipx or fail."
    fi

    log "INFO" "Installing tools from $MISE_CONFIG_SRC..."
    if ! "$MISE_BIN" install; then
        log "WARN" "Some mise tools failed to install. See the report below."
    fi

    export PATH="$MISE_SHIMS:$PATH"
}

install_fzf_git() {
    if [ -f "$HOME/.fzf-git.sh" ]; then
        return 0
    fi
    show_progress "Downloading fzf-git.sh"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL https://raw.githubusercontent.com/junegunn/fzf-git.sh/main/fzf-git.sh -o "$HOME/.fzf-git.sh"
    else
        wget -qO "$HOME/.fzf-git.sh" https://raw.githubusercontent.com/junegunn/fzf-git.sh/main/fzf-git.sh
    fi
    finish_progress
}

report() {
    local missing_system=() missing_mise=() shadowed=()
    local entry cmd mise_path other_path

    for entry in "${SYSTEM_TOOLS[@]}"; do
        cmd="${entry%%:*}"
        command -v "$cmd" >/dev/null 2>&1 || missing_system+=("$cmd")
    done
    command -v docker >/dev/null 2>&1 || missing_system+=("docker")

    for cmd in "${MISE_COMMANDS[@]}"; do
        # Disabled on purpose on this machine (see keep_native_claude)
        if [ "$cmd" = "claude" ] && grep -qs '"claude"' "$HOME/.config/mise/conf.d/local.toml"; then
            continue
        fi
        if ! mise_path="$("$MISE_BIN" which "$cmd" 2>/dev/null)"; then
            missing_mise+=("$cmd")
            continue
        fi
        # Another copy elsewhere on the original PATH (system package, old manual install)
        other_path="$(PATH="$ORIG_PATH" command -v "$cmd" 2>/dev/null || true)"
        if [ -n "$other_path" ] && [ "$other_path" != "$mise_path" ] && [[ "$other_path" != "$MISE_SHIMS"/* ]]; then
            shadowed+=("$cmd ($other_path)")
        fi
    done

    echo ""
    echo "==================================== REPORT ===================================="
    if [ ${#missing_mise[@]} -gt 0 ]; then
        log "WARN" "mise did not provide: ${missing_mise[*]}. Run 'mise install' again to see the errors."
    else
        log "INFO" "All mise/uv tools installed."
    fi

    if [ ${#missing_system[@]} -gt 0 ]; then
        if [ "$SUDO_ACCESS" = "no" ]; then
            log "WARN" "Not available from mise/uv and missing on this system: ${missing_system[*]}. Ask an admin to install them, or skip them."
        else
            log "WARN" "Still missing after the package manager step: ${missing_system[*]}."
        fi
        case " ${missing_system[*]} " in
        *" zsh "*) log "WARN" "Without zsh, your zsh config won't load; setup.sh adds mise to .bashrc instead." ;;
        esac
        case " ${missing_system[*]} " in
        *" docker "*) log "INFO" "docker is installed by install_desktop.sh on your machines; on servers it's up to the admin." ;;
        esac
    else
        log "INFO" "All system tools present."
    fi

    if [ ${#shadowed[@]} -gt 0 ]; then
        log "WARN" "Other copies of mise-managed tools are on your PATH. mise's take priority once it's activated in your shell, but remove these to avoid confusion: ${shadowed[*]}"
    fi
    echo "================================================================================"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
    log "INFO" "Starting CLI installation (sudo: $SUDO_ACCESS, OS: $OS_ID)"
    mkdir -p "$HOME/.local/bin"
    export PATH="$HOME/.local/bin:$PATH"

    if [ "$SUDO_ACCESS" = "yes" ]; then
        detect_pkg_manager
        install_system_tools
    else
        log "INFO" "No sudo: skipping system packages."
    fi

    install_mise
    link_mise_config
    keep_native_claude
    setup_github_token
    install_mise_tools
    install_fzf_git

    report
    log "INFO" "Done. Open a new shell (or run 'exec zsh') to pick up the tools. Update everything later with 'mise up'."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
