fzf_default_opts=(
  "--color dark"
  "--color bg+:236,pointer:7,prompt:-1"
  "--color hl:3:underline,hl+:3:underline,info:-1,spinner:-1"
  "--tabstop=4"
  "--layout=reverse"
  "--info=hidden"
  "--no-bold"
  "--height=30%"
)
export FZF_DEFAULT_OPTS="${fzf_default_opts[*]}"

relative_path() {
  if [[ "$PWD" == ~  || "$PWD" == ~/src ]]; then
    # From a performance perspective this is very unfortunate.
    cat
  fi
  sed "s#^$PWD/\(.*\)#\1#g"

  # this is old
  # # One with just the relative path and one with the full path.
  # sed "s#^\($PWD/\)\(.*\)#\2\\"$'\n'"\1\2#g"
}

filter_exists() {
  while IFS= read -r line; do
    if [[ -e "$line" ]]; then
      echo "$line"
    fi
  done
}

filter_file() {
  for i in {1..2}; do
    while IFS= read -r line; do
      if [[ -f "$line" ]]; then
        echo "$line"
        break
      fi
    done
  done
}

quick_paths() {(
  # We run in a subshell to avoid modifying parent history.
  fc -R

  # Ensures only absolute paths and the first argument are printed.
  # The reason we expand bookmarks is to handle old bookmarks appropriately.
  fc -lnr 1 | grep "^\(e\|cd\) [/~]" | sed -E "s#^(e|cd) ([^[:space:]]*).*#\2#g" | expand_bookmarks | grep -F "$PWD/"
  fd -aH -d3 .
  scd fd -aH -d3 . 2> /dev/null

  fc -lnr 1 | grep "^\(e\|cd\) [/~]" | sed -E "s#^(e|cd) ([^[:space:]]*).*#\2#g" | expand_bookmarks

  echo ~dotfiles
  fd -H . ~dotfiles
  echo ~notes
  fd -H . ~notes

  echo ~/src
  fd -H -d2 . ~/src

  if [[ -d ~/Downloads ]]; then
    echo ~/Downloads
    fd -d2 . ~/Downloads
  fi

  if [ -e ~Pictures/2020 ]; then
    echo ~Pictures/2020
    fd -H . ~Pictures/2020
  fi
  if [ -e ~Pictures/2021 ]; then
    echo ~Pictures/2021
    fd -H . ~Pictures/2021
  fi
  if [ -e ~Pictures/2022 ]; then
    echo ~Pictures/2022
    fd -H . ~Pictures/2022
  fi

  local depth=""
  if ! git rev-parse >/dev/null 2>&1; then
    depth="-d3"
  fi
  fd "$depth" -aH .
  scd fd "$depth" -aH . 2> /dev/null
  if [[ "${FD_ALL-}" ]]; then
    fd "$depth" -aI .
    scd fd "$depth" -aI . 2> /dev/null
  fi
)}

replace_bookmarks() {
  local sed_expr=""
  for b in "${(Oa)bookmarks[@]}"; do
    local full_path="$b"
    local name="~${b##*/}"

    sed_expr+="; s#^$full_path\$#$name#g"
    sed_expr+="; s#^$full_path/#$name/#g"
  done
  sed_expr+="; s#^$HOME#~#g"

  # Must use gsed here as this expression can get long and BSD sed appears to have a limit
  # on the expression size.
  gsed "$sed_expr"
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

  # See above.
  gsed "$sed_expr"
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
  selected=("${(@f)$(quick_paths | grep -Fv ".pxd/" | grep -Fxv "$PWD/" | filter_exists | relative_path \
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
      if [[ "$equick_path" == *.CR3 ]]; then
        execi o "$qquick_path"
      elif [[ "$equick_path"  == *.pxd ]]; then
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

get-last-files() {
  # This needs to be kept in sync with the pipeline in fzf-quick-paths!
  quick_paths | filter_file | relative_path | replace_bookmarks
}

zle-line-init() {
  # Why does the below line cause zsh to complain:
  # zle-line-init:local:11: not valid in this context: last-file
  # local last-file="$(get-last-file)"
  unset EDITOR_LINE
  if [[ -e "$NVIM_FZF_TYPE" ]]; then
    local fzf_type
    fzf_type="$(<"$NVIM_FZF_TYPE")"
    unset NVIM_FZF_TYPE
    case "$fzf_type" in
      paths)
        fzf-quick-paths
        ;;
      last-file)
        # sed '2!d' grabs the second last file.
        execute=1 execi e "$(get-last-files | sed '2!d')"
        ;;
      paths-all)
        fzf-quick-paths-all
        ;;
      rg)
        fzf-rg
        ;;
      gcn)
        execute=1 gcn
        execute=1 execi e "$(get-last-files | head -n1)"
        ;;
    esac
  fi
}
zle -N zle-line-init
