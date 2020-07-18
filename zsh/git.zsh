alias g="git"
gch() {
  if [[ "$#" -eq 1 ]]; then
    if [ ! "$(git branch --list "$@")" ]; then
      git branch "$@"
    fi
  fi
  git checkout "$@"
}
alias gcm="git commit"
alias gcma="gcm --amend"
alias gcme="gcm --amend --no-edit"
gcmf() {
  if [[ ! "$@" ]]; then
    set -- HEAD
  fi
  git commit --fixup "$@"
}
ga() {
  if [[ ! "$@" ]]; then
    set -- -A
  fi
  git add "$@"
}
alias gb="git branch"
alias gpl="git pull"
alias gf="git fetch"
alias gp="git_push"
alias gpf="git_push -f"
alias gs="git status"
alias gsh="git show"
alias gst="git stash"
alias gstk="git stash --keep-index"
alias gl="git log"
alias gls="git log --pretty=oneline --decorate"
alias glp="git log --patch"
alias gcl="git clone"
alias grv="git revert"
alias gro="git remote"
alias grm="git rm"
alias gcp="git cherry-pick"
alias gm="git merge"
alias gt="git tag"
alias gbl="git blame"

alias gd="git diff"
alias gdc="git diff --cached"
alias gdd="git difftool"
alias gddc="git difftool --cached"

alias grb="git rebase"
alias grbi="git rebase --interactive"
alias grbc="git rebase --continue"
alias grbe="git rebase --edit-todo"
alias grbs="git rebase --skip"
alias grba="git rebase --abort"

alias grt="git reset"
alias grth="git reset --hard"

alias c="gae && gcm"

gcd() {
  local root_dir
  root_dir="$(git rev-parse --show-toplevel)"
  if [[ ! "$root_dir" ]]; then
    return 1
  fi

  cd "$root_dir"
  if [[ "$#" -gt 0 ]]; then
    eval "$@"
    local exit_code="$?"
    prevd
    return "$exit_code"
  fi
}

scd() {
  local super
  super="$(git rev-parse --show-superproject-working-tree)"
  if [[ ! "$super" ]]; then
    gcd "$@"
    return
  fi

  cd "$(git rev-parse --show-superproject-working-tree)"
  if [[ "$#" -gt 0 ]]; then
    eval "$@"
    local exit_code="$?"
    prevd
    return "$exit_code"
  fi
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

  mkdir -p "$(dirname "$dst")"
  if git clone --recursive "https://github.com/$repo_path" "$dst"; then
    cd "$dst"
  fi
}

alias gy="gitsync"
gitsync() {(
  set -euo pipefail

  sh_c() {
    if [[ "${DRY_RUN-}" ]]; then
      echo "+ $*"
    else
      sh -c "$*"
    fi
  }

  if [[ "${1-}" == "--dry-run" ]]; then
    DRY_RUN=1
  fi

  git fetch

  current_branch="$(git rev-parse --abbrev-ref HEAD)"
  branches=("${(@f)$(git branch | sed 's#^. ##' || true)}")
  for b in "${branches[@]}"; do
    if ! remote="$(git config --get "branch.$b.remote")"; then
      # No remote so skip.
      continue
    fi

    # If the remote branch hasn't been deleted, we just fetch it.
    if git branch -r | grep -qF "$remote/$b"; then
      sh_c git checkout -q "$b"
      sh_c git pull -q
      sh_c git checkout -q -
      echo "pulled $b"
      continue
    fi

    if [[ "$current_branch" == "$b" ]]; then
      sh_c git checkout -q master
    fi
    sh_c git branch -qD "$b"
    echo "deleted $b"
  done
)}

gho() {(
  set -euo pipefail

  if [[ "$#" -gt 0 ]]; then
    url="https://github.com/$*"
    o "$url"
    return
  fi

  url="$(git remote get-url origin | sed -e 's#https://github.com/##' -e 's#.git$##' )"
  url="https://github.com/$url"
  branch="$(git rev-parse --abbrev-ref HEAD 2> /dev/null || true)"
  if [[ "$branch" != "HEAD" && "$branch" != "master" ]]; then
    if true || hub pr list -h "$branch" &> /dev/null; then
      # Automatically opens either the PR for this branch or shows
      # the page to open the PR.
      #
      # Very neat.
      url+="/pull/$branch"
    fi
  fi

  echo "$url"
  if command_exists o; then
    o "$url"
  fi
)}

alias ghf="gh repo fork --remote"
ghc() {
  gh repo create "$@" | cat &&
  ghd "${@[-1]}"
}

git_push() {(
  set -euo pipefail

  # If there is no remote tracking branch and the arguments are
  # empty, then set upstream.
  if ! git rev-parse "@{u}" &> /dev/null && [[ "$#" -eq 0 ]]; then
    git -c push.default=current push -u
    return
  fi

  git push "$@"
)}

alias gae="git_add_edit"
git_add_edit() {(
  set -euo pipefail

  patch_file="$(mktemp)"
  git diff "$@" > "$patch_file"
  if [[ ! -s "$patch_file" ]]; then
    return
  fi

  sed -i.bak -e '/^+++ /!s/^+/# +/' "$patch_file"
  sed -i.bak -e '/^--- /!s/^-/# -/' "$patch_file"

  e "$patch_file"

  sed -i.bak -e '/^# +/d' "$patch_file"
  sed -i.bak -e 's/^# -/ /' "$patch_file"

  EDITOR="sh -c 'cp "$patch_file" \$1' -s" git add -e
)}
