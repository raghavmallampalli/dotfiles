#!/bin/zsh

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
