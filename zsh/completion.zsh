ZSH_AUTOSUGGEST_USE_ASYNC=1
source ~zsh/zsh-autosuggestions/zsh-autosuggestions.zsh
bindkey "^v" autosuggest-execute

# Color 153 from https://jonasjacek.github.io/colors/.
# https://stackoverflow.com/a/62008734/4283659
zstyle ":completion:*:default" list-colors ${(s.:.)NHOOYR_LS_COLORS} "ma=48;5;153;1"
# Binds Shift + Tab reverse completion.
# https://stackoverflow.com/a/842370/4283659
bindkey "^[[Z" reverse-menu-complete

zstyle ":completion:*" list-dirs-first true
zstyle ":completion:*" group-name ""
# _approximate is not default.
zstyle ':completion:*' completer _complete _ignored _approximate
# Full case insensitive and then substring match if that returns nothing.
zstyle ':completion:*' matcher-list 'm:{[:lower:][:upper:]}={[:upper:][:lower:]}' '+l:|=* r:|=*'
zstyle ":completion:*" menu select yes
zstyle ":completion:*" list-prompt %B%p%b
zstyle ":completion:*" select-prompt %B%p%b
zstyle ':completion:*' use-cache true

# Always reloads command list before completing.
# https://bbs.archlinux.org/viewtopic.php?id=175388
# http://www.zsh.org/mla/users/2006/msg00181.html
zstyle ":completion:*" rehash true

# Disables ~<USER> completion. Way too many normally.
# I only want to see my bookmarks.
zstyle ":completion:*" users

autoload -U compinit
# See https://github.com/zsh-users/zsh-completions/issues/433#issuecomment-346395881 for -i.
# Allows sharing compinit with root.
compinit -i
