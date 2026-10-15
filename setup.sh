#!/bin/bash

# setup.sh - link the dotfiles and configure the shell. Run after install_cli.sh.
#
# Dotfiles are managed by chezmoi, with this repo as its source (see home/). Every managed
# path in $HOME is a symlink into the repo, like stow: editing a config edits the repo, and
# new files in a linked directory (e.g. ~/.config/niri) land in the repo too.

set -e
set -u
set -o pipefail

export BACKUP_DIR="${BACKUP_DIR:-$HOME/.local/state/dotfiles-backup/$(date +%Y%m%d_%H%M%S)}"
source "$(dirname "$0")/common.sh"

trap 'cleanup ${LINENO} $?' EXIT

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
# Tools installed by install_cli.sh
export PATH="$HOME/.local/bin:${XDG_DATA_HOME:-$HOME/.local/share}/mise/shims:$PATH"

SET_LOCAL_TIME=""
GH_LOGIN=""
SET_ZSH_DEFAULT=""
SUDO_ACCESS=""

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -t, --local-time <y/n>         Set hardware clock to local time? (Windows dual boot)"
    echo "  -g, --github-login <y/n>       Log in to GitHub?"
    echo "  -z, --zsh-default <y/n>        Set zsh as default shell?"
    echo "  --sudo-access <yes/no>         Do you have sudo access? Only used as a fallback for"
    echo "                                 setting your own login shell if plain 'chsh' fails."
    echo "  -h, --help                     Show this help message"
    echo ""
    echo "If any option is not provided, the script will prompt."
    exit 0
}

while getopts ":t:g:z:h-:" opt; do
    case $opt in
    -)
        case "${OPTARG}" in
        local-time)
            SET_LOCAL_TIME="${!OPTIND:-}"
            OPTIND=$((OPTIND + 1))
            ;;
        github-login)
            GH_LOGIN="${!OPTIND:-}"
            OPTIND=$((OPTIND + 1))
            ;;
        zsh-default)
            SET_ZSH_DEFAULT="${!OPTIND:-}"
            OPTIND=$((OPTIND + 1))
            ;;
        sudo-access)
            SUDO_ACCESS="${!OPTIND:-}"
            OPTIND=$((OPTIND + 1))
            ;;
        help) show_help ;;
        *)
            echo "Unknown option: --${OPTARG}"
            show_help
            ;;
        esac
        ;;
    t) SET_LOCAL_TIME="$OPTARG" ;;
    g) GH_LOGIN="$OPTARG" ;;
    z) SET_ZSH_DEFAULT="$OPTARG" ;;
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

# Collect answers up front so the rest runs unattended
if is_wsl; then
    SET_LOCAL_TIME="n"
elif [ -z "$SET_LOCAL_TIME" ]; then
    read -p "Set hardware clock to local time? (only for Windows dual boot) [y/n] " SET_LOCAL_TIME
fi

if command -v gh >/dev/null 2>&1; then
    log "INFO" "Currently logged in GitHub accounts:"
    gh auth status 2>/dev/null || echo "Not logged in to any GitHub accounts"
    if [ -z "$GH_LOGIN" ]; then
        read -p "Log in to GitHub? [y/n] " GH_LOGIN
    fi
fi

if [ -z "$SET_ZSH_DEFAULT" ]; then
    read -p "Set zsh as default shell? [y/n] " SET_ZSH_DEFAULT
    SET_ZSH_DEFAULT=${SET_ZSH_DEFAULT:-n}
fi

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

setup_ssh_key() {
    if [ -f "$HOME/.ssh/id_ed25519" ]; then
        return 0
    fi
    if ! command -v ssh-keygen >/dev/null 2>&1; then
        log "WARN" "ssh-keygen not found; skipping SSH key generation."
        return 0
    fi
    show_progress "Generating SSH key"
    mkdir -p "$HOME/.ssh"
    ssh-keygen -q -t ed25519 -C "$(whoami)@$(uname -n)" -f "$HOME/.ssh/id_ed25519" -N ""
    eval "$(ssh-agent -s)" >/dev/null 2>&1
    ssh-add -q "$HOME/.ssh/id_ed25519"
    finish_progress
}

setup_local_time() {
    if [[ $SET_LOCAL_TIME = y ]]; then
        show_progress "Setting hardware clock to local time"
        execute timedatectl set-local-rtc 1 --adjust-system-clock
        finish_progress
    fi
}

setup_github() {
    if ! command -v gh >/dev/null 2>&1; then
        log "WARN" "GitHub CLI not installed (run install_cli.sh). Add $HOME/.ssh/id_ed25519.pub to github.com manually."
        return 0
    fi
    if [[ $GH_LOGIN = y ]]; then
        gh auth login
    fi
}

link_dotfiles() {
    # Resolve the real binary, not mise's shim: the cleanup below also removes the link to
    # mise's config, after which the shim can't find chezmoi anymore
    local chezmoi
    chezmoi="$(mise which chezmoi 2>/dev/null || command -v chezmoi || true)"
    if [ -z "$chezmoi" ]; then
        log "ERROR" "chezmoi not found. Run install_cli.sh first."
        exit 1
    fi

    # Point chezmoi at this repo so plain `chezmoi apply` works later too
    local chezmoi_conf="${XDG_CONFIG_HOME:-$HOME/.config}/chezmoi/chezmoi.toml"
    if [ ! -f "$chezmoi_conf" ]; then
        mkdir -p "$(dirname "$chezmoi_conf")"
        printf 'sourceDir = "%s"\n' "$REPO_ROOT" >"$chezmoi_conf"
        log "INFO" "Wrote $chezmoi_conf"
    elif ! grep -q "sourceDir = \"$REPO_ROOT\"" "$chezmoi_conf"; then
        log "WARN" "$chezmoi_conf exists with a different sourceDir; using $REPO_ROOT for this run."
    fi

    # Clear whatever is at each managed path first: old symlinks (e.g. from stow) are
    # removed, real files and directories are backed up to $BACKUP_DIR
    show_progress "Linking dotfiles"
    local target
    while IFS= read -r target; do
        backup_and_delete "$target"
    done < <("$chezmoi" --source "$REPO_ROOT" managed --include=symlinks --path-style=absolute)

    "$chezmoi" --source "$REPO_ROOT" apply --force
    finish_progress
}

setup_zsh() {
    if ! command -v zsh >/dev/null 2>&1; then
        log "WARN" "zsh not installed; staying on bash. Adding mise to .bashrc so the tools are on PATH."
        if ! grep -q "mise activate bash" "$HOME/.bashrc" 2>/dev/null; then
            cat >>"$HOME/.bashrc" <<'EOF2'

# mise-managed tools (added by dotfiles setup.sh; zsh wasn't available)
if [ -x "$HOME/.local/bin/mise" ]; then
    eval "$("$HOME/.local/bin/mise" activate bash)"
fi
EOF2
        fi
        return 0
    fi

    mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}/zsh" "${XDG_STATE_HOME:-$HOME/.local/state}/zsh"

    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        log "INFO" "Installing Oh-My-Zsh"
        KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    fi

    local plugin_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions"
    if [ ! -d "$plugin_dir" ]; then
        git clone --quiet https://github.com/zsh-users/zsh-autosuggestions "$plugin_dir"
    fi

    if [[ $SET_ZSH_DEFAULT = y ]] && [ "$SHELL" != "$(command -v zsh)" ]; then
        set_login_shell
    fi
}

# chsh is normally self-service and works without sudo for your own account, so try that
# first. With sudo, target the current user explicitly - this only ever changes your shell.
# Note: chsh only accepts shells listed in /etc/shells.
set_login_shell() {
    local zsh_path
    zsh_path="$(command -v zsh)"
    if chsh -s "$zsh_path" 2>/dev/null; then
        log "INFO" "Login shell changed to zsh. Takes effect after logout."
        return 0
    fi
    if [ "$SUDO_ACCESS" = "yes" ] && run_command chsh -s "$zsh_path" "$(whoami)"; then
        log "INFO" "Login shell changed to zsh via sudo. Takes effect after logout."
        return 0
    fi

    log "WARN" "Could not change login shell. Starting zsh from .bashrc instead."
    if ! grep -q "ZSH_STARTED" "$HOME/.bashrc" 2>/dev/null; then
        cat >>"$HOME/.bashrc" <<'EOF'

# Auto-start zsh (chsh unavailable or not permitted)
if [ -t 1 ] && [ -z "$ZSH_STARTED" ] && command -v zsh >/dev/null 2>&1; then
    export ZSH_STARTED=1
    exec zsh
fi
EOF
    fi
}

# tmux plugins live under ~/.config/tmux/plugins (git-ignored), so bootstrap TPM and
# install the plugins from tmux.conf using a throwaway tmux server.
setup_tmux() {
    if ! command -v tmux >/dev/null 2>&1; then
        return 0
    fi
    local tmux_conf="${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf"
    local plugins_dir="${XDG_CONFIG_HOME:-$HOME/.config}/tmux/plugins"
    local tpm_dir="$plugins_dir/tpm"

    # Check for the tpm executable, not just the directory: a broken partial checkout
    # would otherwise be treated as installed
    if [ ! -x "$tpm_dir/tpm" ]; then
        log "INFO" "Installing TPM (tmux plugin manager)"
        rm -rf "$tpm_dir"
        mkdir -p "$plugins_dir"
        git clone --quiet https://github.com/tmux-plugins/tpm "$tpm_dir"
    fi

    if [ -f "$tmux_conf" ]; then
        local sock="tpm-setup-$$"
        TERM="${TERM:-xterm-256color}" tmux -L "$sock" new-session -d -x 200 -y 50 2>/dev/null || true
        tmux -L "$sock" source-file "$tmux_conf" 2>/dev/null || true
        tmux -L "$sock" run-shell "$tpm_dir/bindings/install_plugins" 2>/dev/null || true
        tmux -L "$sock" kill-server 2>/dev/null || true
        if tmux has-session 2>/dev/null; then
            tmux source-file "$tmux_conf" 2>/dev/null || true
        fi
        log "INFO" "tmux plugins installed. Manage later with prefix+I / prefix+U."
    fi
}

setup_bat() {
    if command -v bat >/dev/null 2>&1; then
        mkdir -p "$(bat --config-dir)/themes"
    fi
}

# An ipython profile with a Catppuccin theme, for `uvx ipython`-style scratch sessions
setup_ipython() {
    if ! command -v uv >/dev/null 2>&1; then
        return 0
    fi
    local ipython_config="$HOME/.ipython/profile_default/ipython_config.py"
    if grep -q "catppuccin_theme" "$ipython_config" 2>/dev/null; then
        return 0
    fi
    uv run --with ipython --with catppuccin ipython profile create >/dev/null
    cat <<'EOF' >>"$ipython_config"

from IPython.utils.PyColorize import linux_theme, theme_table
from copy import deepcopy

catppuccin_theme = "catppuccin-mocha"
theme = deepcopy(linux_theme)
theme.base = catppuccin_theme
theme_table[catppuccin_theme] = theme

c.TerminalInteractiveShell.true_color = True
c.TerminalInteractiveShell.colors = catppuccin_theme
EOF
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
    log "INFO" "Starting setup (backups go to $BACKUP_DIR)"
    setup_ssh_key
    if ! is_wsl; then
        setup_local_time
    fi
    setup_github
    link_dotfiles
    setup_zsh
    setup_tmux
    setup_bat
    setup_ipython
    log "INFO" "Setup completed. Restart your shell."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
