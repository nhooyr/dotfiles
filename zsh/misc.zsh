# Otherwise delete by word deletes over slashes.
# https://stackoverflow.com/questions/444951/zsh-stop-backward-kill-word-on-directory-delimiter
autoload -U select-word-style
select-word-style bash

# Bash"s time format is much better.
# ZSH"s default is a single line.
# https://superuser.com/a/71890
TIMEFMT="real    %*E
user    %*U
sys     %*S"

if [[ -f /dev/tty ]]; then
  tabs -2 > /dev/tty
fi
setopt AUTO_CD
setopt AUTO_PUSHD
setopt PUSHD_SILENT
setopt EXTENDED_GLOB
setopt INTERACTIVE_COMMENTS
setopt NOBEEP
setopt CDABLE_VARS
setopt NO_CASE_GLOB

# Required explicitly for tmux.
bindkey -e

autoload -U edit-command-line
zle -N edit-command-line
bindkey "\ee" edit-command-line

prepend-noti() {
  LBUFFER="n $LBUFFER"
}
zle -N prepend-noti
bindkey "\el" prepend-noti

append-ampersands() {
  LBUFFER+=" && "
}
zle -N append_ampersands
bindkey "\el" append_ampersands
