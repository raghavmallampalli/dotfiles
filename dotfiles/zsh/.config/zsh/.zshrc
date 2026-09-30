#!/bin/zsh

# XDG Compliance for Zsh files
export ZSH_COMPDUMP="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump"
mkdir -p "${ZSH_COMPDUMP:h}"
export HISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history"
mkdir -p "${HISTFILE:h}"

# Choose Starship configuration based on TTY and Nerd Font availability
if [[ "$FORCE_NERD_FONT" == "1" || "$USE_NERD_FONTS" == "1" ]]; then
  export STARSHIP_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/starship.toml"
elif [[ "$(tty)" == /dev/tty[0-9]* || "$TERM" == "linux" ]]; then
  export STARSHIP_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/starship-no-nerd.toml"
elif command -v fc-list >/dev/null 2>&1 && ! fc-list : family | grep -iq "Nerd Font"; then
  export STARSHIP_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/starship-no-nerd.toml"
else
  export STARSHIP_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/starship.toml"
fi

if [ -f $ZDOTDIR/.aliases ]; then
  source $ZDOTDIR/.aliases
fi
if [ -f $ZDOTDIR/.env_vars ]; then
  source $ZDOTDIR/.env_vars
fi

# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME=""

# Add wisely, as too many plugins slow down shell startup.
plugins=(git dotenv zsh-autosuggestions zoxide fzf nvm uv docker starship)

source $ZSH/oh-my-zsh.sh

# Catppuccin Mocha-inspired colors for GNU ls. Set the palette explicitly so
# inherited distro LS_COLORS rules (including their bright yellow file types)
# do not take precedence. 256-color approximations of the Mocha palette:
# blue 111, teal 116, green 150, mauve 183, red 210, peach 216, yellow 223.
export LS_COLORS='di=38;5;111:ow=38;5;111;48;5;235:tw=38;5;111;48;5;235:ln=38;5;116:mi=38;5;210:or=38;5;210:so=38;5;218:pi=38;5;223:ex=38;5;150:bd=38;5;223:cd=38;5;223:su=38;5;210:sg=38;5;223:ca=38;5;210:*.png=38;5;216:*.jpg=38;5;216:*.jpeg=38;5;216:*.gif=38;5;216:*.webp=38;5;216:*.bmp=38;5;216:*.tif=38;5;216:*.tiff=38;5;216:*.svg=38;5;216:*.heic=38;5;216:*.pdf=38;5;183:*.doc=38;5;216:*.docx=38;5;216:*.odt=38;5;216:*.rtf=38;5;216:*.txt=38;5;116:*.md=38;5;116:*.csv=38;5;116:*.tsv=38;5;116:*.json=38;5;116:*.yaml=38;5;116:*.yml=38;5;116:*.toml=38;5;116:*.zip=38;5;183:*.gz=38;5;183:*.bz2=38;5;183:*.xz=38;5;183:*.7z=38;5;183:*.rar=38;5;183:*.tar=38;5;183:*.mp3=38;5;218:*.flac=38;5;218:*.wav=38;5;218:*.ogg=38;5;218:*.mp4=38;5;218:*.mkv=38;5;218:*.mov=38;5;218:*.webm=38;5;218'

# Enable autossh and ssa auto-completion using ssh completion
compdef autossh=ssh
compdef ssa=ssh

# If set to true, tmux will auto-attach to a session if not already in one
########################### ATTACH TO TMUX SESSION ###########################
if [[ $TMUX_AUTO_ATTACH = true ]]; then
  SESSION_NAME="General"
  # Auto-attach to tmux session if not already in one
  if [[ -z ${TMUX} ]]; then
    # Check if session exists and is not attached
    if tmux ls 2>/dev/null | grep -qE "${SESSION_NAME}:.*?attached"; then
      echo "Session exists and is attached, force attach with ta -t ${SESSION_NAME}"
    else
      # If session exists attach to it, otherwise create new session
      if tmux has-session -t ${SESSION_NAME} 2>/dev/null; then
        tmux -u attach -t ${SESSION_NAME}
      else
        tgex
      fi
    fi
  fi
fi

##################################################################################

# Change directory with yazi
function yy() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")"
	yazi "$@" --cwd-file="$tmp"
	if cwd="$(cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
		cd -- "$cwd"
                zle reset-prompt
	fi
	rm -f -- "$tmp"
}

icp() {
    rsync --archive --verbose --compress --progress "$@"
}

bindkey -v
setopt nonomatch # allows globbing (name* matching in apt, ls etc.), use with caution
[[ -a /etc/zsh_command_not_found ]] && . /etc/zsh_command_not_found
setopt SHARE_HISTORY
setopt HIST_IGNORE_SPACE

# vi at terminal
bindkey 'jk' vi-cmd-mode
bindkey 'kj' vi-cmd-mode
autoload edit-command-line; zle -N edit-command-line
bindkey -M vicmd V edit-command-line

# fzf
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
source <(fzf --zsh)
[ -f ~/.fzf-git.sh ] && source ~/.fzf-git.sh

# Prevent Ctrl-S from stopping
stty -ixon
