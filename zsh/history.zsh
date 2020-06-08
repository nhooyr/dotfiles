# Disables control flow so that Ctrl + S works
# for forward history search.
# https://superuser.com/a/1067896
if [[ -t 0 ]]; then
  stty -ixon
fi

# Disables the beep on ambigous completion.
unsetopt LIST_BEEP

HISTFILE=~/.zsh_history
HISTSIZE=100000
SAVEHIST=100000

setopt HIST_REDUCE_BLANKS
setopt EXTENDED_HISTORY
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_SAVE_NO_DUPS
setopt INC_APPEND_HISTORY
setopt APPEND_HISTORY

# Fish style history search.
# https://unix.stackexchange.com/a/97844
bindkey "\ep" history-beginning-search-backward
bindkey "\en" history-beginning-search-forward
