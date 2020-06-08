# Otherwise delete by word deletes over slashes.
# https://stackoverflow.com/questions/444951/zsh-stop-backward-kill-word-on-directory-delimiter
autoload -U select-word-style
select-word-style bash

# Bash"s time format is much better.
# ZSH"s default is a single line.
# https://superuser.com/a/71890
TIMEFMT="
real    %*E
user    %*U
sys     %*S"

if [[ -t 0 ]]; then
  tabs -2
fi
setopt AUTO_CD
setopt AUTO_PUSHD
setopt PUSHD_SILENT
setopt EXTENDED_GLOB
setopt INTERACTIVE_COMMENTS
setopt NOBEEP
setopt CDABLE_VARS

autoload -U edit-command-line
zle -N edit-command-line
bindkey "\ee" edit-command-line
