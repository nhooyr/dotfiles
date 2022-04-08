alias g="git"
alias gb="git branch -vv"
alias gbr="git branch -rvv"
# This does not work with upstream tracking branches. So annoying.
# anything not origin i mean.
#   gch upstream/my-branch
# will create a new local branch named the entire thing above with the random suffix.
gch() {(
  set -euo pipefail

  if [[ "$#" -eq 1 ]]; then
    if [ "$1" = "-" ] || [ -f "$1" ]; then
      git checkout "$@"
      return
    fi

    # Check if the passed argument is just a commit.
    if [ "$1" = "$(git rev-parse "$1" 2>&1)" ]; then
      git checkout "$@"
      return
    fi

    if [ ! "$(git branch --list "$*")" ] && [ ! "$(git branch --list --remote "origin/$*")" ]; then
      set "$*-$(xxd -p -l 2 /dev/urandom)"
      git branch "$@"
    fi
  fi
  git checkout "$@"
)}
_gch() {
  compadd "${(@f)$(git for-each-ref '--format=%(refname:short)')}"
  # To complete branches that only exist remotely.
  compadd "${(@f)$(git for-each-ref '--format=%(refname:short)' | \
    git for-each-ref '--format=%(refname:short)' | \
    grep origin/ | \
    sed 's#origin/##')}"
}
# zsh's git completion is very slow and git's zsh completion is just a wrapper around
# the bash completion and doesn't define a zsh completion service for git checkout.
compdef _gch gch
alias gs="git status"
alias gcm="git commit"
gcmf() {(
  set -euo pipefail

  if [ ! "$*" ]; then
    local last_non_fixup
    last_non_fixup="$(git log --pretty=oneline -n100 | grep -v fixup | head -n1 | awk '{ print $1}')" || true
    if [ ! "$last_non_fixup" ]; then
      last_non_fixup="HEAD"
    fi
    set -- "$last_non_fixup"
  fi
  git commit --fixup "$@"
)}
compdef _git gcmf=_git_recent_commits
gacmp() {
  ga "$@" && gcm && git_push
}
compdef _git gacmp=git-add
gcmp() {
  gcm "$@" && git_push
}
compdef _git gcmp=git-commit
gacp() {
  gac "$@" && git_push
}
compdef _git gacp=git-add
alias fcm="ga . && gcme && gpf"
alias gcma="gcm --amend"
alias gcme="gcm --amend --no-edit"
alias gcmd='gcm --message "$(date-full)"'
ga() {
  if [[ ! "$@" ]]; then
    set -- -A
  fi
  git add "$@"
}
compdef _git ga=git-add
alias gap="git add -p"
alias gai="git add -i"
gac() {
  whilet gae "$@" '&&' gcm
  git_push
}
compdef _git gac=git-add
alias gbd="git branch -d"
alias gpl="git pull"
alias gf="git fetch --all"
alias gp="git_push"
alias gps="GIT_PUSH_SYNC=1 git_push"
alias gpf="git_push -f"
alias gsh="git show"
gshs() {
  git show --no-patch --format=%s "$@"
}
gshb() {
  git show --no-patch --format=%b "$@"
}
alias gst="git stash"
alias gstp="git stash pop"
alias gstpu="git stash push"
alias gstk="git stash --keep-index"
alias gstd="git stash drop"
alias gstl="git stash list"
alias gsts="git stash show -p"
alias gstn="git stash save"
alias gl="git log"
alias gls="git log --pretty=oneline"
alias glp="git log --patch"
# For finding the commit for a merge.
alias glm="git log --topo-order"
alias gcl="git clone"
alias grv="git revert"
alias gro="git remote"
alias grm="git rm"
alias gcp="git cherry-pick"
alias gcpa="git cherry-pick --abort"
alias gm="git merge"
alias gt="git tag"
alias gbl="git blame"

alias gd="git diff"
alias gdc="gd --cached"
alias gdd="git difftool"
alias gddc="git difftool --cached"

alias grb="git rebase"
grbi() {
  if [ "$*" = "" ]; then
    set -- origin/master
  fi
  git rebase --interactive "$@"
}
grbif() {
  if [ -n "$*" ]; then
    # Include the passed commit.
    set -- "${@:1:-1}" "${@:-1}~1"
  fi
  git rebase --interactive "$@"
}
compdef _git grbi=git-rebase
alias grbc="git rebase --continue"
alias grbe="git rebase --edit-todo"
alias grbs="git rebase --skip"
alias grba="git rebase --abort"

alias grt="git reset"
alias grth="git reset --hard"

alias gcherry="git cherry -v --abbrev=8 origin/master"

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

  cd "$super"
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

  local dst="$2"
  if [[ ! "$dst" ]]; then
    dst="$HOME/src/$repo_path"
    if [[ -d "$dst" ]]; then
      cd "$dst"
      return
    fi
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
      echo "+ $*" >&2
    else
      sh -c "$*"
    fi
  }

  if [[ "${1-}" == "--dry-run" ]]; then
    DRY_RUN=1
  fi

  git fetch --all --force | tr '[:upper:]' '[:lower:]'

  if [[ "$(sh_c git stash)" != "No local changes to save" ]]; then
    local STASHED=1
  fi

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
      sh_c git pull -q --force
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

  if [[ "${STASHED-}" ]]; then
    sh_c git stash pop --quiet
  fi
)}

gh_url() {
  if [[ "$#" -gt 0 ]]; then
    echo "https://github.com/$*"
    return
  fi

  repo_path="$(git remote get-url origin | sed -e 's#https://github.com/##' -e 's#.git$##' )"
  echo "https://github.com/$repo_path"
}

ghi() {(
  set -euo pipefail

  url="$(gh_url "$@")/issues/new"

  echo "$url"
  if command_exists o; then
    o "$url"
  fi
)}

gho() {(
  set -euo pipefail

  url="$(gh_url "$@")"
  # edit: wait hold on, when can this even fail?
  if [[ "$#" -eq 0 ]]; then
    branch="$(git rev-parse --abbrev-ref HEAD 2> /dev/null || true)"
    if [[ "$branch" != "HEAD" && "$branch" != "master" ]]; then
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
  gh repo create -y "$@" &&
  ghd "${@[-1]}"
}

git_push() {(
  set -euo pipefail

  # If there is no remote tracking branch and the arguments are
  # empty, then set upstream first.
  if ! git rev-parse "@{u}" &> /dev/null && [[ "$#" -eq 0 || "$*" == "-f" ]]; then
    local branch
    branch="$(git rev-parse --abbrev-ref HEAD)"
    set -- -u "$@" origin "+$branch:$branch"
  fi

  if [ ${GIT_PUSH_SYNC-} ]; then
    unset GIT_PUSH_SYNC
    git push "$@"
    return
  fi

  # It gives status info on stderr so we have to redirect both.
  git push "$@" &> /dev/null &!
)}
_git_push() {
  compadd "${(@f)$(git remote)}"
}
# The default git push completion includes directories for some reason...
compdef _git_push git_push

wait-push() {
  whilet '!' git status '|' grep -q 'Your branch is up to date'
}

alias gae="git_add_edit"
git_add_edit() {(
  set -euo pipefail

  patch_file="$(mktemp "/tmp/$(git rev-parse --show-toplevel | sed 's#.*/##')-stage.patch-XXXXXX")"
  # Cannot easily uncomment deleted files.
  # The patch indicates it's been "renamed" to ./dev/null and
  # deleted. Perhaps at some point in the future I wrote some Go
  # to handle this correctly.
  git diff --diff-filter=d "$@" > "$patch_file"
  if [[ ! -s "$patch_file" ]]; then
    return
  fi

  # TODO: Add untracked files to the diff and if uncommented,
  # add them to the index.
  #
  # Likewise with deleted files.
  for file in "${(@f)$(git ls-files --exclude-standard -o)}"; do
  done

  sed -i.bak -e '/^+++ /!s/^+/# +/' "$patch_file"
  sed -i.bak -e '/^--- /!s/^-/# -/' "$patch_file"

  e "$patch_file"

  sed -i.bak -e '/^# +/d' "$patch_file"
  sed -i.bak -e 's/^# -/ /' "$patch_file"

  EDITOR="sh -c 'cp "$patch_file" \$1' -s" git add -e
)}

alias gsub="git submodule"
alias gsubi="git submodule update --init"

gsub_file() {(
  set -eu

  git rev-parse --show-toplevel

  submodule_paths=(
    "${(@f)$(git config --file ./.gitmodules --get-regexp "path" | awk '{ print $2 }')}"
  )
  submodule_urls=(
    "${(@f)$(git config --file ./.gitmodules --get-regexp "url" | awk '{ print $2 }')}"
  )
  submodule_branches=(
    "${(@f)$(git config --file ./.gitmodules --get-regexp "branch" | awk '{ print $2 }')}"
  )

  sh_c() {
    echo + "$*"
    if [ "${DRY_RUN-}" ]; then
      return
    fi
    eval "$@"
  }

  for (( i=1; i <= ${#submodule_paths[@]}; i++ )) do
    p="${submodule_paths[$i]}"
    if [ -d "$p" ]; then
      continue
    fi

    url="${submodule_urls[$i]}"
    unset b
    if [ "${submodule_branches[$i]-}" ]; then
      b="-b ${submodule_branches[$i]}"
    fi
    sh_c git submodule add "${b-}" "$url" "$p"
  done
)}

if [[ "$OSTYPE" == darwin* ]]; then
  prepend_PATH /usr/local/share/git-core/contrib/diff-highlight
elif [[ "$DISTRO" == "debian" ]]; then
  prepend_PATH /usr/share/doc/git/contrib/diff-highlight
fi
