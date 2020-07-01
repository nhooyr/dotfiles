alias r="source ~/.zshrc"
alias l="ls -lh"
alias ll="ls -lha"
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
  export QUICK_PATH="$(mktemp -d)/quick_path"
  command "$EDITOR" "$@"
  if [[ ! -e "$QUICK_PATH" ]]; then
    unset QUICK_PATH
  fi
}
alias e.="e ."

export EXA_COLORS="da=reset:uu=reset:gu=reset:ur=33:uw=33:ux=33:ue=33:tx=33:gx=33:sn=reset:sb=reset"
ls() {
  if command_exists exa; then
    set -- "${@/-lh/-l}"
    set -- "${@/-la/-laa}"
    exa -F --group-directories-first "$@"
  elif command_exists gls; then
    gls --indicator-style=classify --color=auto --group-directories-first "$@"
  else
    command ls -GF "$@"
  fi
}
alias lr="l --reverse --sort=size"

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

gcd() {
  cd "$(git rev-parse --show-toplevel)"
  if [[ "$#" -gt 0 ]]; then
    eval "$@"
    prevd
  fi
}

scd() {
  local super="$(git rev-parse --show-superproject-working-tree)"
  if [[ ! "$super" ]]; then
    gcd "$@"
    return
  fi
  cd "$(git rev-parse --show-superproject-working-tree)"
  if [[ "$#" -gt 0 ]]; then
    eval "$@"
    prevd
  fi
}

mcd() {
  mkdir -p "$@"
  cd "$@"
}
compdef _directories mcd

alias chx="chmod +x"
alias md="mkdir -p"

alias g="git"
alias gch="git checkout"
alias ga="git add"
alias gaa="git add -A"
alias gap="git add -p"
alias gcm="git commit -v"
alias gcma="git commit -v --amend"
alias gcmae="git commit -v --amend --no-edit"
alias gcmf="git commit -v --fixup"
alias gb="git branch"
alias grt="git reset"
alias grth="git reset --reset"
alias grb="git rebase"
alias gpl="git pull"
alias gf="git fetch"
alias gfork="git fork && git config remote.pushDefault nhooyr"
alias gp="git push"
alias gpf="git push -f"
alias gs="git status"
alias gst="git stash"
alias gy="git sync"
alias gsh="git show"
alias gd="git diff"
alias gdc="git diff --cached"
alias gdd="git difftool"
alias gddc="git difftool --cached"
alias gl="git log"
alias gpr="git pull-request -p -em ''"
alias gcl="git clone"
alias grv="git revert"
alias gro="git remote"
alias grm="git rm"
alias gcp="git cherry-pick"
alias gm="git merge"
alias gt="git tag"
alias gacm="gaa && gcm"
alias gacmp="gaa && gcm && gp"
alias gcmp="gcm && gp"
alias fcm="gaa && gcm --amend --no-edit && gpf"
alias gbl="git blame"
alias y="yarn -s"
alias ya="yarn -s add"
alias yad="yarn -s add --dev"
alias yd="yarn -s dev"
alias yp="yarn -s prod"
alias yc="yarn -s ci"
alias yf="yarn -s fix"

git() {
  if command_exists hub; then
    hub "$@"
  else
    command git "$@"
  fi
}

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
  echo -ne '\a'
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
  rsync -ah --partial "$@"
}

alias pc="pbcopy"
alias pp="pbpaste"
alias catq="jq -R"

ghd() {
  local repo_path="$1"
  repo_path="${repo_path/*:\/\//}"
  repo_path="${repo_path/github.com\//}"
  repo_path="$(grep -o "^[^/]\+/[^/]\+" <<< "$repo_path")"

  if [[ ! "$repo_path" ]]; then
    echo "invalid url or repo_path"
    return
  fi

  local dst="$HOME/src/$repo_path"
  if [[ -d "$dst" ]]; then
    cd "$dst"
    return
  fi

  mkdir -p "$(dirname "$dst")"
  if git clone --recursive "https://github.com/$repo_path" "$dst"; then
    cd "$dst"
  fi
}

gh() {
  local branch="$(git rev-parse --abbrev-ref HEAD)"
  if [[ ! "$branch" ]]; then
    return
  fi

  if [[ "$(git remote)" = *nhooyr* ]] ; then
    branch="nhooyr:$branch"
  fi
  local url="$(hub pr list -f $'%U\n' -h "$branch" | head -n 1)"
  if [[ ! "$url" ]]; then
    url="$(hub browse -u)"
  fi

  echo "$url"

  if command_exists o; then
    o "$url"
  fi
}

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
