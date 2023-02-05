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

alias xg="xargs -I{}"

alias er="e -R"

es() {
  NVR_FLAGS="-cc new" nvim_terminal_editor "$@"
}

ev() {
  NVR_FLAGS="-cc vnew" nvim_terminal_editor "$@"
}

et() {
  NVR_NO_WAIT=1 NVR_FLAGS="-cc tabnew" nvim_terminal_editor "$@"
}

e() {
  export NVIM_FZF_TYPE="$(mktemp -d)/nvim_fzf_type"
  if [ ! "$NVIM" -a "$NVIM_SESSION" ] && [ -d "$*" ]; then
    cd "$@"
    return
  fi
  "$EDITOR" "$@"
  if [[ ! -e "$NVIM_FZF_TYPE" ]]; then
    unset NVIM_FZF_TYPE
  fi
  # Fuck the below, super anxiety inducing not seeing the diff before every push.
  # It's not so bad anymore with background git pushes.
  # Might be a good idea to run gcn here in foreground after and then I can approve diff
  # after editing each individual file! Will try that at some point.
  #
  # # love this :)
  # # Could not get ~notes working here correctly for some bizarre reason...
  # # if [[ "$*" == ~notes* ]]; then
  # #   Ah ~ bookmarks only expand if there is no additional text near them?
  # #   Noticed when below regexp had \^~notes
  # #   Must be a way to get append/prepend text hmm, welp it's nbd.
  # #   maybe store in a variable first?
  # # - OH HAHA even grep ~notes wasn't correct, I need to check against realpath, not just
  # #   the args..
  # if realpath "$1" | grep -q ~notes; then
  #   # Frequent pushes are great, just not when they block everything :(
  #   # If I open nvim fast enough again it'll fuck up my terminal so we throw out all
  #   # output.
  #   ( gcn &> /dev/null &! )
  # fi
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
    command "$ls" -v --indicator-style=classify --color=auto --group-directories-first "$@"
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
    --no-heading \
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

# https://unix.stackexchange.com/a/541415
alias pc="perl -pe 'chomp if eof' | pbcopy"
alias pcc="cat \$(pp) | pc"
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
  command bc -l <<< "$*"
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
  date "+%Y-%m-%d %I:%M:%S%p"
}

notepath() {
  local notes_subdir=""
  if [ "$#" -gt 0 ]; then
    notes_subdir="/$1"
  fi
  md ~notes"$notes_subdir"
  echo ~notes"$notes_subdir/$(dt).txt"
}
note() {
  e "$(notepath)"
}

# Commits my ~notes repository with the full date/time as the commit message.
gcn() {(
  set -euo pipefail
  cd ~notes
  _gcn
  # cd ~nhooyr-ts/notes
  # _gcn
  rcln
)}
rcln() {
  rclone sync -L --exclude .git/ ~notes/2023 gdrive:/notes/2023
}
_gcn() {
  git add -A
  if git diff --cached --stat | grep -q 'deletions\?(-)'; then
    # We use --edit here so I can see the diff and approve.
    git commit --edit -m "$(date-full)" || true
  else
    git commit -m "$(date-full)" || true
  fi
  git_push
}
bindkey-gcn() {
  execute=1 execi gcn
}
zle -N bindkey-gcn
bindkey "\er" bindkey-gcn

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
ytitle() {
  curl -fsSL "$1" | sed -n 's;.*<title>\(.*\)</title>.*;\1;p'
}

alias grepw='git grep -I "\\s\+\$"'
alias sedw='git grep -Il "" | xargsp -n1 gsed -i "s/\\s\\+\$//g"'

lotto() {
  local output=""
  for (( i = 1; i <= $count; i++)); do
    # See the following:
    # https://stackoverflow.com/questions/63544826/unix-shell-why-are-the-same-random-numbers-repeated
    local r="$RANDOM"
    local n="$(printf "%02d" "$(( $range_start + $r % $range_end ))")"

    if grep -q "$n" <<< "$output"; then
      i=$(($i - 1))
      continue
    fi

    output+="$n
"
  done

  output="$(printf "$output" | sort -n | tr "\n" " ")"
  printf "${output:0:-1}\n"
}

lottomax() {
  local count=7
  local range_start=1
  local range_end=50
  lotto
}

lotto649() {
  local count=6
  local range_start=1
  local range_end=49
  lotto
}

mansects() {
  for dir in "${(@s.:.)$(man -w)}"; do
    echo "$dir"
    l -H "$dir"
  done
}

tire-diameter() {
  local width_mm="$(echo "$1" | sed -n 's;[^0-9]*\([0-9]*\)/.*;\1;p')"
  local sidewall_ratio_pct="$(echo "$1" | sed -n 's;.*/\([0-9]*\)[^0-9].*;\1;p')"
  local wheel_diameter="$(echo "$1" | sed -n 's;.*R\([0-9]*\).*;\1;p')"
  if [ ! "$width_mm" -o ! "$sidewall_ratio_pct" -o ! "$wheel_diameter" ]; then
    echo "usage: tire-diameter <tire-size>
Where tire-size is metric size like XXX/YYRZZ."
    return 1
  fi

  local inches="$(units "$width_mm mm" inches | sed -n 's;.*\* \(.*\);\1;p')"
  local diameter="$(calc "$inches * $sidewall_ratio_pct/100 * 2 + $wheel_diameter")"

  echo "$diameter"
}

alias psqlc="PSQL_PAGER= psql -XAtc"

nses() {
  NVIM_SESSION="$1"

  mkdir -p "$XDG_DATA_HOME/nvim/sessions"
  touch "$XDG_DATA_HOME/nvim/sessions/$NVIM_SESSION.vim"
  NVIM_SESSION="$NVIM_SESSION" \
    EDITOR=nvim_terminal_editor \
    nvim \
    --listen "/tmp/nvim-$NVIM_SESSION" \
    -S "$XDG_DATA_HOME/nvim/sessions/$NVIM_SESSION.vim"
}

trash() {
  md /tmp/trash
  mv "$@" /tmp/trash
}

if [ "$NVIM" -a "$NVIM_SESSION" ]; then
  man() {
    # Without 2> complains about lcd errors from lcd autocmd even though those are
    # prefixed with :silent.
    nvim --server "/tmp/nvim-$NVIM_SESSION" --remote-expr "execute('Man $*')" 2> /dev/null
  }
fi

mcdt() {
  cd "$(mktemp -d)"
}
