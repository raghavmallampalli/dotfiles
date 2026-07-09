export ZDOTDIR=$HOME/.config/zsh
export BASH_ENV="$HOME/.bashrc"

# XDG Compliance for Zsh files
export ZSH_COMPDUMP="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump"
mkdir -p "${ZSH_COMPDUMP:h}"
export HISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history" 
mkdir -p "${HISTFILE:h}"
