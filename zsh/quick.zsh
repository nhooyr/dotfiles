fzf_default_opts=(
  "--color light"
  "--color bg+:153,fg+:-1,pointer:-1,prompt:-1"
  "--color hl:125,hl+:125,info:-1,spinner:-1"
  "--tabstop=4"
  "--layout=reverse"
  "--info=hidden"
  "--no-bold"
)
export FZF_DEFAULT_OPTS="${fzf_default_opts[*]}"

relative_path() {
  if [[ "$PWD" == ~ ]]; then
    cat
  fi
  sed "s#$PWD/##g"
}

quick_paths() {
  # Ensures only absolute paths and the first argument are printed.
  fc -lnr 1 | grep "^\(e\|cd\) [/~]" | sed -E "s#^(e|cd) ([^[:space:]]*).*#\2#g"

  fd -aH -d6 .

  echo ~/src/nhooyr/dotfiles
  fd -H -d1 . ~/src/nhooyr/dotfiles
  fd -H -d2 . ~/src/nhooyr/dotfiles
  fd -H -d3 . ~/src/nhooyr/dotfiles
  fd -H -d6 . ~/src/nhooyr/dotfiles
  fd -H . ~/src/nhooyr/dotfiles

  echo ~/src
  fd -H -d1 . ~/src
  fd -H -d2 . ~/src

  if [[ -d ~/Downloads ]]; then
    echo ~/Downloads
    fd -H -d1 . ~/Downloads
    fd -H -d2 . ~/Downloads
  fi
}

# Used by my neovim config.
normalize() {
  local normalized="$(realpath "$1" | replace_bookmarks)"
  normalized="$(echo "${(q)normalized}" | sed 's/\\~/~/g')"
  echo "$normalized"
}

replace_bookmarks() {
  local sed_expr=""
  for b in "${(Oa)bookmarks[@]}"; do
    local name="~$(basename "$b")"
    local full_path="$(eval "echo $b")"

    sed_expr+="; s#$full_path\$#$name#g"
    sed_expr+="; s#$full_path/#$name/#g"
  done
  sed_expr+="; s#^$HOME#~#g"

  sed "$sed_expr"
}

execi() {
  LBUFFER="$*"
  if [[ "$execute" ]]; then
    zle accept-line
  fi
}

fzf-quick-paths() {
  local word="${LBUFFER##* }"

  local selected
  selected=("${(@f)$(quick_paths | replace_bookmarks | filter_duplicates | \
    fzf --expect=ctrl-v,ctrl-x --height=30% --query="$word")}")
  local key="${selected[1]}"
  local quick_path="${selected[2]}"

  if [[ "$quick_path" ]]; then
    local qquick_path="$(echo "${(q)quick_path}" | sed 's/\\~/~/g')"
    local equick_path="$(eval "echo $qquick_path")"
    if [[ "$key" == "ctrl-v" ]]; then
      local execute=1
    fi
    if [[ ! "$BUFFER" ]]; then
      if [[ -d "$equick_path" ]]; then
        execi cd "$qquick_path"
      elif [[ -e "$equick_path" ]]; then
        if [[ "$key" == "ctrl-x" ]]; then
          execi "$qquick_path"
        else
          execi e "$qquick_path"
        fi
      else
        execi "false $qquick_path"
      fi
    else
      execi "${LBUFFER%$word}$quick_path"
    fi
  fi
  zle reset-prompt
}
zle -N fzf-quick-paths
bindkey "\ev" fzf-quick-paths

fzf-history() {
  local selected
  selected=("${(@f)$(fc -lnr 1 | fzf --expect=ctrl-v --no-sort --height=30% --query="$LBUFFER")}")
  local key="${selected[1]}"
  local cmd="${selected[2]}"
  if [[ "$cmd" ]]; then
    LBUFFER="$cmd"
    if [[ "$key" == "ctrl-v" ]]; then
      zle accept-line
    fi
  fi
  zle reset-prompt
}
zle -N fzf-history
if command_exists fzf; then
  bindkey "^R" fzf-history
fi
