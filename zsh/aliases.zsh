alias r="source ~/.zshrc"
export GREP_COLOR='1;33'
alias grep="grep --color"
# https://unix.stackexchange.com/q/148545/109885
alias s="sudo "
sudo() {
  if [[ "$#" -eq 0 ]]; then
    command sudo -Es
    return
  fi

  local args=""
  for a in "$@"; do
    args+=" ${(q)a}"
  done
  command sudo -E "$SHELL" -ic "$args"
}
alias m="make"
alias pd="prevd"
alias nd="nextd"
alias sshq="ssh -O exit"
alias sshu="ssh -oControlPath=none"
alias rb="s reboot"
alias po="s poweroff"
alias tmux="tmux -S /tmp/tmux"

ses() {
  tmux new -A -s "${1-default}"
}

e() {
  export NVIM_FZF_TYPE="$(mktemp -d)/nvim_fzf_type"
  command "$EDITOR" "$@"
  if [[ ! -e "$NVIM_FZF_TYPE" ]]; then
    unset NVIM_FZF_TYPE
  fi
}
alias e.="e ."

alias l="ls -lh -gG"
alias ll="ls -lha -gG"
ls() {
  if command -v gls > /dev/null; then
    command gls --indicator-style=classify --color=auto --group-directories-first "$@"
  else
    command ls -GF "$@"
  fi
}
alias la="ls -lha"

declare -a prev_dirs
cd() {
  prev_dirs=()
  # Required to make any change into $CDPATH silent.
  builtin cd $1 > /dev/null

  if [[ "$#" -gt 1 ]]; then
    eval "${@:2}"
    prevd
  fi
}

nextd() {
  if [[ "${#prev_dirs[@]}" -eq 0 ]]; then
    echo "forward directory stack empty"
    return 1
  fi
  builtin cd "${prev_dirs[-1]}"
  prev_dirs[-1]=()
  if [[ "$#" -gt 0 ]]; then
    eval "$@"
    prevd
  fi
}

prevd() {
  if popd; then
    prev_dirs+=("$OLDPWD")
    if [[ "$#" -gt 0 ]]; then
      eval "$@"
      nextd
    fi
  fi
}

mcd() {
  mkdir -p "$@"
  cd "$@"
}
compdef _directories mcd

alias chx="chmod +x"
alias md="mkdir -p"

alias y="yarn -s"
alias ya="yarn -s add"
alias yad="yarn -s add --dev"
alias yd="yarn -s dev"
alias yp="yarn -s prod"
alias yc="yarn -s ci"
alias yf="yarn -s fix"

rg() {
  command rg -S \
    --colors match:fg:yellow \
    --colors match:style:nobold \
    --colors line:fg:black \
    --colors path:fg:black \
    "$@"
}
alias rgi="rg --no-ignore --hidden"
alias h="fc -R"
alias n="t noti "
set -o ALIAS_FUNC_DEF
alias t="t "
t() {
  time ("$@")
}
set +o ALIAS_FUNC_DEF

noti() {
  local last_status="$?"
  if [[ "$#" -eq 0 ]]; then
    if [[ "$last_status" -eq 0 ]]; then
      set -- true
    else
      set -- false
    fi
  fi
  "$@"
  last_status="$?"
  echo -ne '\a' >&2
  [[ "$last_status" -eq 0 ]]
}

rs() {
  if [[ "${RSYNC_UNSHARED-}" ]]; then
    set -- -e "ssh -oControlPath=none" "$@"
  fi
  if [[ "${RSYNC_VERBOSE-}" ]]; then
    set -- -v "$@"
  fi
  if [[ "${RSYNC_COMPRESS-}" ]]; then
    set -- -z "$@"
  fi
  if [[ "$(rsync --version)" != *"Copyright (C) 1996-2006 by Andrew Tridgell"* ]]; then
    set -- --info=progress2 "$@"
  else
    # Older rsync included with macOS.
    set -- --progress "$@"
  fi
  rsync -ah --partial "$@" >&2
}

alias pc="pbcopy"
alias pp="pbpaste"
alias catq="jq -R"

up() {
  if [[ "$#" -eq 0 ]]; then
    cd ..
    return
  fi

  # number
  if grep -q "^\d\+$" <<< "$*"; then
    cd "$(printf "../%.0s" {1..$1})"
    return
  fi

  up_d "$@"
}

up_d() {
  local dir="$PWD"
  local pattern="$1"

  while true; do;
    local head="$(basename "$dir")"

    if rg -q "$pattern" <<< "$head"; then
      cd "$dir"
      return
    fi

    if [[ "$dir" == "/" ]]; then
      echo "no match in \$PWD"
      return
    fi

    dir="$(dirname "$dir")"
  done
}

calc() {
  command bc <<< "$*"
}

alias p8="ping 8.8.8.8"
alias we="watchexec"

inf() {
  while; do eval "$@"; done
}

rep() {
  while eval "$@"; do; done
}

alias dr="docker run -it --rm"
alias db="docker build"
alias cv="command -v"
alias tch="touch"
