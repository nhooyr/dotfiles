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
  echo ~/src
  fd -H -d2 . ~/src
  fd -H . ~/src/nhooyr/dotfiles
  fd -aH -d4 .
}

quick_paths_fzf() {
  local word="${LBUFFER##* }"

  local selected
  selected="$(quick_paths | relative_path | human_path | awk '!seen[$0]++' | fzf +s --height 40% --query "$word" | expand_tilde)"
  if [[ ! "$BUFFER" ]]; then
    if [[ -d "$selected" ]]; then
      cd "$selected"
    elif [[ -e "$selected" ]]; then
      $EDITOR "$selected"
    fi
  else
    LBUFFER="${LBUFFER%$word}${selected}"
  fi
  zle reset-prompt
}
zle -N quick-paths-fzf quick_paths_fzf

bindkey "\ev" quick-paths-fzf

source_if_exists "/usr/local/opt/fzf/shell/completion.zsh"
source_if_exists "/usr/local/opt/fzf/shell/key-bindings.zsh"
