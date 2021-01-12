alias r="source ~/.zshrc"
export GREP_COLOR='4;33'
alias grep="grep --color"
# https://unix.stackexchange.com/q/148545/109885
alias s="sudo "
sudo() {
  if [[ "$#" -eq 0 ]]; then
    command sudo -Es
    return
  fi

  local args=""
  local flags=()
  for a in "$@"; do
    # While args is empty, if the next argument starts
    # with - then it is a flag for sudo.
    if [[ "$args" == "" && "$a" == -*  ]]; then
      flags+=("$a")
      continue
    fi

    args+=" ${(q)a}"
  done
  command sudo -E "${flags[@]}" "$SHELL" -ic "$args"
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

alias l="ls -lh -gG"
alias ll="ls -lha -gG"
ls() {
  local ls="ls"
  if hash gls 2> /dev/null; then
    ls="gls"
  fi
  if [[ "$ls" == "gls" || "$OSTYPE" == linux-* ]]; then
    # GNU ls.
    command "$ls" --indicator-style=classify --color=auto --group-directories-first "$@"
  else
    # BSD ls.
    command ls -GF "$@"
  fi
}
alias la="ls -lha"
alias lt="ll -t"
alias lS="ll -S"

declare -a prev_dirs
cd() {
  if [[ -f "$*" ]]; then
    set -- "$(dirname "$*")"
  fi

  prev_dirs=()
  # Required to make any change into $CDPATH silent.
  builtin cd $1 > /dev/null

  if [[ "$#" -gt 1 ]]; then
    run_quoted "${@:2}"
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
    run_quoted "$@"
    prevd
  fi
}

prevd() {
  if popd; then
    prev_dirs+=("$OLDPWD")
    if [[ "$#" -gt 0 ]]; then
      run_quoted "$@"
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
alias mkdir="mkdir -p"
alias md="mkdir"

alias y="yarn -s"
alias ya="y add"
alias yad="y add --dev"
alias yu="y upgrade"
alias yua="y upgrade --latest"
alias yd="y dev"
alias yp="y prod"
alias yc="y ci"
alias yf="y fix"
alias yt="y test"
alias yb="y build"
alias yl="y link"

rg() {
  command rg -S \
    --colors match:fg:yellow \
    --colors match:style:nobold \
    --hidden \
    -g '!.git' \
    "$@"
}
alias rgi="rg --no-ignore --hidden"
alias h="fc -R"
# We set ESCAPE_ALL_ARGS as we're we want noti
# to get the escaped version of the args.
alias n="ESCAPE_ALL_ARGS=1 t noti "
alias t="timeq"
timeq() {
  # We use a sub shell here instead of
  # run_quoted time "$@"
  # as sometimes zsh's builtin time does not print anything.
  # It only prints a measurement always when ran against a subshell.
  time (run_quoted "$@")
}

noti() {
  local last_status="$?"
  if [[ "$#" -eq 0 ]]; then
    if [[ "$last_status" -eq 0 ]]; then
      set -- true
    else
      set -- false
    fi
  fi
  run_quoted "$@"
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
oc() {
  watchexec 'echo change' | \
  while IFS= read -r line; do
    clear
    print -P "%B%F{blue}=%f%b"
    run_quoted "$@"
    print -P "%B%F{green}=%f%b"
  done
}

whilet() {
  while run_quoted "$@"; do; done
}

inf() {
  while; do run_quoted "$@"; done
}

alias d="docker"
dr() {(
  set -euo pipefail

  if [ -f "${@[-1]}" ]; then
    local image_id
    image_id="$(db -f "${@[-1]}" .)"
    set -- "${@:1:-1}" "$image_id"
  fi

  docker run -it --rm -v "$PWD:/mnt/pwd" -w /mnt/pwd "$@"
)}
compdef _docker dr=docker-run

db() {
  docker build "$@" >&2 && \
    docker build -q "$@"
}
compdef _docker db=docker-build

alias cv="command -v"
alias tch="touch"

alias kb="kubectl"
alias mv="mv -i"

raws() {(
  set -euo pipefail

  md jpegs && mv -i *.JPG jpegs || true
  md raws && mv -i *.CR3 raws || true
  if ls -1 | grep -iq '\.mp4$' ; then
    md vids && mv -i *.mp4 vids || true
  fi
  md out
)}

dt() {
  date "+%Y/%m/%d"
}

# See nvim/neosnippets/_.snip
date-full() {
  date "+%Y-%m-%d,%I:%M:%S%p"
}

note() {
  local notes_subdir=""
  if [ "$#" -gt 0 ]; then
    notes_subdir="$1"
  fi
  cd ~notes"/$notes_subdir" e "$(dt).md"
}

# Commits my ~notes repository with the full date/time as the commit message.
gcn() {(
  set -euo pipefail
  cd ~notes
  git add -A
  git commit -m "$(date-full)" || true
  git push
)}

# https://askubuntu.com/a/634655
# --add-metadata
#   Adds metadata to the file.
# -f bestaudio[ext=m4a]
#   Output the best m4a quality file available.
#   Without ext, it'll be a webm which doesn't support thumbnails.
# --embed-thumbnail
#   Embed the thumbnail into the m4a.
#
# I wanted to use opus as the format but youtube doesn't seem to support it! Would have to
# re-encode the audio. youtube seems to only support m4a, mp4 and webm. Of which m4a is
# best for obvious reasons. Though perhaps I should look into webm more.
alias yaudio="youtube-dl --add-metadata -f 'bestaudio[ext=m4a]' --embed-thumbnail"

alias rgw='git grep -I "\\s\+\$"'
alias sw='git grep -Il "" | xargs -n1 gsed -i "s/\\s\\+\$//g"'
