fzf_default_opts=(
  "--color light"
  "--color bg+:153,fg+:-1,pointer:-1,prompt:-1"
  "--color hl:125,hl+:125,info:-1,spinner:-1"
  "--tabstop=4"
  "--layout=reverse"
  "--info=hidden"
  "--no-bold"
  "--tiebreak=index"
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
  # The reason we expand bookmarks is to handle old bookmarks appropriately.
  fc -lnr 1 | grep "^\(e\|cd\) [/~]" | sed -E "s#^(e|cd) ([^[:space:]]*).*#\2#g" | expand_bookmarks | grep -F "$PWD/"
  fc -lnr 1 | grep "^\(e\|cd\) [/~]" | sed -E "s#^(e|cd) ([^[:space:]]*).*#\2#g" | expand_bookmarks

  fd -aH -d6 .

  echo ~src/dotfiles
  fd -H . ~dotfiles

  echo ~/src
  fd -H -d2 . ~/src

  if [[ -d ~/Downloads ]]; then
    echo ~/Downloads
    fd -d2 . ~/Downloads
  fi
}

replace_bookmarks() {
  local sed_expr=""
  for b in "${(Oa)bookmarks[@]}"; do
    local full_path="$b"
    local name="~${b##*/}"

    sed_expr+="; s#^$full_path\$#$name#g"
    sed_expr+="; s#^$full_path/#$name/#g"
  done
  sed_expr+="; s#^$HOME#~#g"

  sed "$sed_expr"
}

expand_bookmarks() {
  local sed_expr=""
  for b in "${(Oa)bookmarks[@]}"; do
    local full_path="$b"
    local name="~${b##*/}"

    sed_expr+="; s#^$name\$#$full_path#g"
    sed_expr+="; s#^$name/#$full_path/#g"
  done
  sed_expr+="; s#^~#$HOME#g"

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
        execi cd "$qquick_path "
      else
        if [[ "$key" == "ctrl-x" ]]; then
          execi "$qquick_path"
        else
          execi e "$qquick_path"
        fi
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
