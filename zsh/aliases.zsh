alias e="\$EDITOR"
alias r="source ~/.zshrc"
alias l="ls -lh"
alias ll="ls -lha"
alias grep="grep --color"
# https://unix.stackexchange.com/q/148545/109885
alias s="sudo "
alias sudo="sudo "
alias m="man"
alias uti="mdls -name kMDItemContentTypeTree"

ls() {
  if command -v gls > /dev/null; then
    gls --indicator-style=classify --color=auto --group-directories-first "$@"
  else
    command ls -GF "$@"
  fi
}

declare -a prev_dirs
cd() {
  prev_dirs=()
  # Required to make any change into $CDPATH silent.
  builtin cd "$@" > /dev/null
}

nextd() {
  if [[ "${#prev_dirs[@]}" -eq 0 ]]; then
    return
  fi
  builtin cd "${prev_dirs[-1]}"
  prev_dirs[-1]=()
}

prevd() {
  popd "$@" && 
    prev_dirs+=("$OLDPWD")
}

zle-nextd() {
  nextd
  zle reset-prompt
}
zle -N zle-nextd

zle-prevd() {
  prevd 2> /dev/null
  zle reset-prompt
}
zle -N zle-prevd

bindkey "\ep" zle-prevd
bindkey "\en" zle-nextd

gcd() {
  cd "$(git rev-parse --show-toplevel)"
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
alias gcmf="git commit -v --fixup"
alias gb="git branch"
alias grt="git reset"
alias grb="git rebase"
alias gpl="git pull"
alias gf="git fetch"
alias gp="git push"
alias gpf="git push -f"
alias gs="git status"
alias gst="git stash"
alias gy="git sync"
alias gsh="git show"
alias gd="git diff"
alias gdc="git diff --cached"
alias gl="git log"
alias gpr="git pull-request -p"
alias gcl="git clone"
alias grv="git revert"
alias gro="git remote"
alias grm="git rm"
alias gcp="git cherry-pick"
alias gm="git merge"
alias gt="git tag"
alias y="yarn -s"
alias ya="yarn -s add"
alias yad="yarn -s add --dev"
alias yd="yarn -s dev"
alias yp="yarn -s prod"
alias yc="yarn -s ci"
alias yf="yarn -s fix"
alias o="open"

alias git="hub"
alias rg="rg -S"
alias rgi="rg -S --no-ignore --hidden"
alias h="fc -R"
alias n="time noti "
alias rs="rsync -avzP"
alias pc="pbcopy"
alias pp="pbpaste"
alias catq="jq -R"

alias gcmp="gaa && gcm && gp"
alias fcm="gaa && gcm --amend --no-edit && gpf"

noti() {
  "$@"
  osascript -e beep
}

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

  mkdir -p "$dst" &&
    if git clone --recursive "https://github.com/$repo_path" "$dst"; then
      cd "$dst"
    else
      rm -Rf "$dst"
    fi
}

gh() {
  local branch="$(git rev-parse --abbrev-ref HEAD)"
  if [[ ! "$branch" ]]; then
    return
  fi

  local url="$(hub pr list -f $'%U\n' -h "$branch" | head -n 1)"
  if [[ ! "$url" ]]; then
    url="$(hub browse -u)"
  fi

  open "$url"
}

up() {
  if [[ "$#" -eq 0 ]]; then
    cd ..
    return
  fi

  # number
  if grep -q "^\d\+$" <<< "$*"; then
    cd "$(printf '../%.0s' {1..$1})"
    return
  fi

  up_d "$@"
}

up_d() {
  local dir="$PWD"
  local pattern="$1"

  while true; do;
    local head="$(basename "$dir")"

    if grep -q "$pattern" <<< "$head"; then
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
