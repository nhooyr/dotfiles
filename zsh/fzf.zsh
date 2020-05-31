export FZF_DEFAULT_OPTS="--color light,bg+:153,fg+:-1,pointer:-1,prompt:-1,hl:125,hl+:125,info:-1,spinner:-1 --tabstop=4 --layout=reverse --info=hidden --no-bold"

human_path() {
  sed "s#^$HOME#~#g"
}

expand_tilde() {
  sed "s#^~#$HOME#g"
}

relative_path() {
  sed "s#$PWD/##g"
}

quick_paths() {
  fd -aH -d4 .
  echo ~/src
  fd -H -d2 . ~/src
  fd -H . ~/src/nhooyr/dotfiles
}

append_history() {
  "$@"
  print -s -- "$*"
}

fzf_quick_paths() {
  local word="${LBUFFER##* }"

  local selected
  selected="$(quick_paths | relative_path | human_path | awk '!seen[$0]++' | fzf --no-sort --height=40% --query="$word" | expand_tilde)"
  if [[ "$selected" ]]; then
    if [[ ! "$BUFFER" ]]; then
      if [[ -d "$selected" ]]; then
        append_history cd "$selected"
      elif [[ -e "$selected" ]]; then
        append_history $EDITOR "$selected"
      fi
    else
      LBUFFER="${LBUFFER%$word}${selected}"
    fi
  fi
  zle reset-prompt
}
zle -N fzf-quick-paths fzf_quick_paths
bindkey "\ev" fzf-quick-paths

fzf_history() {
  local selected
  IFS=$'\n' selected=($(fc -lnr 1 | fzf --expect=ctrl-v --no-sort --height=40% --query="$BUFFER"))
  if [[ "$selected" ]]; then
    LBUFFER="$selected"
    if [[ ${#selected[@]} -eq 2 ]]; then
      LBUFFER="${selected[2]}"
      zle accept-line
    fi
  fi
  zle reset-prompt
}
zle -N fzf-history fzf_history
bindkey "^R" fzf-history

source_if_exists "/usr/local/opt/fzf/shell/completion.zsh"
