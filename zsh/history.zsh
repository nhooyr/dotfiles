# Disables control flow so that Ctrl + S works
# for forward history search.
# https://superuser.com/a/1067896
stty -ixon

# Disables the beep on ambigous completion.
unsetopt LIST_BEEP

mkdir -p ~/.local/share/zsh
HISTFILE=~/.local/share/zsh/history
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
bindkey "^p" history-beginning-search-backward
bindkey "^n" history-beginning-search-forward
