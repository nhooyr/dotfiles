export FZF_DEFAULT_OPTS="--color light,bg+:153,fg+:-1,pointer:-1,prompt:-1,hl:125,hl+:125,info:-1,spinner:-1 --tabstop=4 --layout=reverse --info=hidden --no-bold --exact"

insert_tilde() {
  sed "s#^$HOME#~#g"
}

expand_tilde() {
  sed "s#^~#$HOME#g"
}

relative_path() {
  sed "s#$PWD/##g"
}

quick_paths() {
  fd -aH -d1 .
  fd -aH -d2 .
  fd -aH -d3 .
  fd -aH -d4 .
  echo ~/src
  fd -H -d1 . ~/src
  fd -H -d2 . ~/src
  fd -H -d1 . ~/src/nhooyr/dotfiles
  fd -H -d2 . ~/src/nhooyr/dotfiles
  fd -H -d3 . ~/src/nhooyr/dotfiles
  fd -H -d4 . ~/src/nhooyr/dotfiles
  fd -H . ~/src/nhooyr/dotfiles
  echo ~/Downloads
  fd -H -d1 . ~/Downloads
  fd -H -d2 . ~/Downloads
}

execi() {
  local cmd="$(sed "s#$HOME#~#g" <<< "$*")"

  LBUFFER="$cmd"
  zle accept-line
}

fzf-quick-paths() {
  local word="${LBUFFER##* }"

  local selected
  selected=("${(@f)$(quick_paths | relative_path | insert_tilde | awk '!seen[$0]++' | \
    fzf --expect=ctrl-v,ctrl-x --no-sort --height=40% --query="$word" | expand_tilde )}")
  if [[ "$selected" ]]; then
    local key="${selected[1]}"
    local quick_path="${selected[2]}"

    if [[ "$quick_path" != /* ]]; then
      quick_path="$PWD/$quick_path"
    fi

    if [[ ! "$BUFFER" ]]; then
      if [[ -d "$quick_path" ]]; then
        execi cd "$quick_path"
      elif [[ -e "$quick_path" ]]; then
        if [[ "$key" == "ctrl-x" ]]; then
          execi "$quick_path"
        else
          execi e "$quick_path"
        fi
      fi
    else
      LBUFFER="${LBUFFER%$word}${quick_path}"
    fi
  fi
  zle reset-prompt
}
zle -N fzf-quick-paths
bindkey "\ev" fzf-quick-paths

fzf-history() {
  local selected
  selected=("${(@f)$(fc -lnr 1 | fzf --expect=ctrl-v --no-sort --height=40% --query="$LBUFFER")}")
  if [[ "$selected" ]]; then
    local key="${selected[1]}"
    local cmd="${selected[2]}"

    LBUFFER="$cmd"
    if [[ "$key" == "ctrl-v" ]]; then
      zle accept-line
    fi
  fi
  zle reset-prompt
}
zle -N fzf-history
bindkey "^R" fzf-history
