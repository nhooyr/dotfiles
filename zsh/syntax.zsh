if [[ "${#ZSH_HIGHLIGHT_STYLES[@]}" -eq 0 ]]; then
  source ~zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi
ZSH_HIGHLIGHT_STYLES=()
ZSH_HIGHLIGHT_STYLES[reserved-word]="fg=magenta"
ZSH_HIGHLIGHT_STYLES[precommand]="fg=yellow"
ZSH_HIGHLIGHT_STYLES[commandseparator]="fg=magenta"
ZSH_HIGHLIGHT_STYLES[globbing]="fg=magenta"
ZSH_HIGHLIGHT_STYLES[history-expansion]="fg=magenta"
ZSH_HIGHLIGHT_STYLES[single-quoted-argument]="fg=green"
ZSH_HIGHLIGHT_STYLES[double-quoted-argument]="fg=green"
ZSH_HIGHLIGHT_STYLES[dollar-quoted-argument]="fg=green"
ZSH_HIGHLIGHT_STYLES[rc-quote]="fg=magenta"
# ZSH_HIGHLIGHT_STYLES[dollar-double-quoted-argument]="fg=black"
ZSH_HIGHLIGHT_STYLES[dollar-double-quoted-argument]="fg=yellow"
ZSH_HIGHLIGHT_STYLES[back-double-quoted-argument]="fg=magenta"
ZSH_HIGHLIGHT_STYLES[back-dollar-quoted-argument]="fg=magenta"
ZSH_HIGHLIGHT_STYLES[redirection]="fg=magenta"
ZSH_HIGHLIGHT_STYLES[comment]="fg=244"
