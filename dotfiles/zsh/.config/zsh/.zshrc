#!/bin/zsh

# XDG Compliance for Zsh files
export ZSH_COMPDUMP="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump"
mkdir -p "${ZSH_COMPDUMP:h}"
HISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history" 

if [ -f $ZDOTDIR/.aliases ]; then
  source $ZDOTDIR/.aliases
fi
if [ -f $ZDOTDIR/.env_vars ]; then
  source $ZDOTDIR/.env_vars
fi

# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time Oh My Zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="powerlevel10k/powerlevel10k"

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(git dotenv conda-zsh-completion zsh-autosuggestions zoxide fzf)
# Add wisely, as too many plugins slow down shell startup.
plugins=(git dotenv conda-zsh-completion zsh-autosuggestions zoxide fzf)

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
######################### POWERLEVEL10K INSTANT PROMPT ###########################

# Customising prompt: powerlevel10k
# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ${XDG_CONFIG_HOME:-$HOME/.config}/p10k.zsh ]] || source ${XDG_CONFIG_HOME:-$HOME/.config}/p10k.zsh

# DO NOT MOVE THIS BLOCK ABOVE THE ATTACH TO TMUX SESSION BLOCK
# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
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

# Customising prompt: powerlevel10k
# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
# [[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
# Correcting logic for p10k location
[[ ! -f $ZDOTDIR/.p10k.zsh ]] || source $ZDOTDIR/.p10k.zsh

# fzf
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
source <(fzf --zsh)
[ -f ~/.fzf-git.sh ] && source ~/.fzf-git.sh

# Prevent Ctrl-S from stopping
stty -ixon

# Set timezone based on IP address
# Only sets for terminal - system is left unaffected 
# useful for multiple timezone clusters
export TZ=$(curl -s --max-time 2 https://ipapi.co/timezone)
