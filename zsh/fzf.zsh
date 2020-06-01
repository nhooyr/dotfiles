export FZF_DEFAULT_OPTS="--color light,bg+:153,fg+:-1,pointer:-1,prompt:-1,hl:125,hl+:125,info:-1,spinner:-1 --tabstop=4 --layout=reverse --info=hidden --no-bold"

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
  fd -H . ~/src/nhooyr/dotfiles
  echo ~/Downloads
  fd -H -d1 . ~/Downloads
  fd -H -d2 . ~/Downloads
}

append_history() {
  local cmd="$(sed "s#$HOME#~#g" <<< "$*")"

  print -s -- "$cmd"
  fc -W
  fc -R
  eval "$cmd"
}

fzf_quick_paths() {
  local word="${LBUFFER##* }"

  local selected
  selected=("${(@f)$(quick_paths | relative_path | insert_tilde | awk '!seen[$0]++' | \
    fzf --expect=ctrl-v --no-sort --height=40% --query="$word" | expand_tilde )}")
  if [[ "$selected" ]]; then
    local key="${selected[1]}"
    local quick_path="${selected[2]}"

    if [[ ! "$BUFFER" ]]; then
      if [[ -d "$quick_path" ]]; then
        append_history cd "$quick_path"
      elif [[ -e "$quick_path" ]]; then
        if [[ "$key" == "ctrl-v" ]]; then
          if [[ "$quick_path" != /* ]]; then
            quick_path="./$quick_path"
          fi
          append_history "$quick_path"
        else
          append_history e "$quick_path"
        fi
      fi
    else
      LBUFFER="${LBUFFER%$word}${quick_path}"
    fi
  fi
  zle reset-prompt
}
zle -N fzf-quick-paths fzf_quick_paths
bindkey "\ev" fzf-quick-paths

fzf_history() {
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
zle -N fzf-history fzf_history
bindkey "^R" fzf-history

source_if_exists "/usr/local/opt/fzf/shell/completion.zsh"
