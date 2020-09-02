fzf_default_opts=(
  "--color light"
  "--color bg+:12,fg+:-1,pointer:-1,prompt:-1"
  "--color hl:3,hl+:3,info:-1,spinner:-1"
  "--tabstop=4"
  "--layout=reverse"
  "--info=hidden"
  "--no-bold"
  "--height=30%"
)
export FZF_DEFAULT_OPTS="${fzf_default_opts[*]}"

relative_path() {
  if [[ "$PWD" == ~  || "$PWD" == ~/src ]]; then
    cat
  fi
  sed "s#^$PWD/##g"
}

filter_exists() {
  while IFS= read -r line; do
    if [[ -e "$line" ]]; then
      echo "$line"
    fi
  done
}

quick_paths() {
  # Ensures only absolute paths and the first argument are printed.
  # The reason we expand bookmarks is to handle old bookmarks appropriately.
  fc -lnr 1 | grep "^\(e\|cd\) [/~]" | sed -E "s#^(e|cd) ([^[:space:]]*).*#\2#g" | expand_bookmarks | grep -F "$PWD/"
  fd -aH -d3 .

  fc -lnr 1 | grep "^\(e\|cd\) [/~]" | sed -E "s#^(e|cd) ([^[:space:]]*).*#\2#g" | expand_bookmarks

  echo ~src/dotfiles
  fd -H . ~dotfiles

  if [ -e ~Pictures ]; then
    echo ~Pictures
    fd -H . ~Pictures
  fi

  echo ~/src
  fd -H -d2 . ~/src

  if [[ -d ~/Downloads ]]; then
    echo ~/Downloads
    fd -d2 . ~/Downloads
  fi

  fd -aH .
  gcd fd -aH . 2> /dev/null
  if [[ "${FD_ALL-}" ]]; then
    fd -aI .
    gcd fd -aI . 2> /dev/null
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

bookmark_pwd() {
  replace_bookmarks <<< "$PWD"
}

# Used by my neovim config.
normalize() {
  local normalized="$(realpath "$1" | replace_bookmarks)"
  normalized="$(echo "${(q)normalized}" | sed 's/\\~/~/g')"
  echo "$normalized"
}

fzf-quick-paths() {
  local query="${LBUFFER##* }"

  local selected
  selected=("${(@f)$(fc -R && quick_paths | grep -Fxv "$PWD" | filter_exists | relative_path \
    | replace_bookmarks | filter_duplicates \
    | fzf --bind=alt-a:toggle-sort --bind=alt-v:toggle-sort --expect=ctrl-v,ctrl-x --query="$query")}")
  local key="${selected[1]}"
  local quick_path="${selected[2]}"

  if [[ "$quick_path" ]]; then
    if [[ "$quick_path" != /* && "$quick_path" != \~* ]]; then
      quick_path="$(bookmark_pwd)/$quick_path"
    fi
    local qquick_path="$(echo "${(q)quick_path}" | sed 's/\\~/~/g')"
    local equick_path="$(eval "echo $qquick_path")"
    if [[ "$key" == "ctrl-v" ]]; then
      local execute=1
    fi
    if [[ ! "$BUFFER" ]]; then
      if [[ "$equick_path" == *.CR3 || "$equick_path"  == *.pxd ]]; then
        execi o -a '"Pixelmator Pro"' "$qquick_path"
      elif [[ -d "$equick_path" ]]; then
        execi cd "$qquick_path "
      elif [[ "$key" == "ctrl-x" ]]; then
        execi "$qquick_path"
      else
        execi e "$qquick_path"
      fi
    else
      execi "${LBUFFER%$query}$quick_path"
    fi
  fi
  zle reset-prompt
}
zle -N fzf-quick-paths
bindkey "\ev" fzf-quick-paths

fzf-quick-paths-all() {
  FD_ALL=1 fzf-quick-paths
}
zle -N fzf-quick-paths-all
bindkey "\ei" fzf-quick-paths-all

fzf-history() {
  local selected
  selected=("${(@f)$(fc -RI && fc -lnr 1 | fzf --bind=ctrl-r:toggle-sort --expect=ctrl-v --tiebreak=index --query="$LBUFFER")}")
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

fzf-rg() {
  local selected
  selected=("${(@f)$(rg --no-heading --line-number --color=always "" \
    | fzf --ansi --expect=ctrl-v)}")
  local key="${selected[1]}"
  local match=("${(@s.:.)selected[2]}")
  if [[ "$match" ]]; then
    local file="$(bookmark_pwd)/${match[1]}"
    if [[ "$key" == "ctrl-v" ]]; then
      local execute=1
    fi

    if [[ ! "$BUFFER" ]]; then
      if [[ "$execute" ]]; then
        export EDITOR_LINE="${match[2]}"
      fi
      execi e "$file"
    else
      execi "$LBUFFER$file"
    fi
  fi
  zle reset-prompt
}
zle -N fzf-rg
bindkey "\et" fzf-rg

fzf-commits() {
  if ! git rev-parse --show-toplevel &> /dev/null; then
    return
  fi
  local query="${LBUFFER##* }"

  local selected
  selected=("${(@f)$(gls | \
    fzf --bind=ctrl-g:toggle-sort --expect=ctrl-v --tiebreak=index --query="$query")}")
  local key="${selected[1]}"
  local commit="$(echo "${selected[2]}" | awk '{ print $1 }' )"
  if [[ "$commit" ]]; then
    if [[ "$key" == "ctrl-v" ]]; then
      local execute=1
    fi
    execi "${LBUFFER%$query}$commit"
  fi
  zle reset-prompt
}
zle -N fzf-commits
if command_exists fzf; then
  bindkey "^g" fzf-commits
fi

zle-line-init() {
  unset EDITOR_LINE
  if [[ -e "$NVIM_FZF_TYPE" ]]; then
    local fzf_type
    fzf_type="$(<"$NVIM_FZF_TYPE")"
    unset NVIM_FZF_TYPE
    case "$fzf_type" in
      paths)
        fzf-quick-paths
        ;;
      paths-all)
        fzf-quick-paths-all
        ;;
      rg)
        fzf-rg
        ;;
    esac
  fi
}
zle -N zle-line-init
