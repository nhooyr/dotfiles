alias e="\$EDITOR"
alias r="source ~/.zshrc"
alias l="ls -lh"
alias ll="ls -lha"
alias up="cd .."
alias nd="pushd"
alias pd="popd"
alias grep="grep --color"
# https://unix.stackexchange.com/q/148545/109885
alias s="sudo "
alias sudo="sudo "

ls() {
  if command -v gls > /dev/null; then
    gls --indicator-style=classify --color=auto --group-directories-first "$@"
  else
    command ls -GF "$@"
  fi
}

# Required to make any change into $CDPATH silent.
cd() {
  builtin cd "$@" > /dev/null
}

gcd() {
  cd "$(git rev-parse --show-toplevel)"
}

mcd() {
  mkdir -p "$@"
  cd "$@"
}

alias chx="chmod +x"
alias md="mkdir -p"

alias g="git"
alias gch="git checkout"
alias ga="git add"
alias gaa="git add -A"
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
alias t="time"
alias n="noti /usr/bin/time -p"
alias rs="rsync -avzP"
alias pc="pbcopy"
alias pp="pbpaste"
alias catq="jq -R"

alias gcmp="gaa && gcm && gp"
alias fcm="gaa && gcm --amend --no-edit && gpf"


#function ghd
#    set -l path $argv[1]
#    set -l path (string replace -r ".*://" "" "$path")
#    set -l path (string replace "github.com/" "" "$path")
#    set -l path (string split / "$path")
#    set -l path (string join / $path[1..2])
#    if [ -z $path ]
#        echo "invalid URL or path"
#        return
#    end
#
#    set -l dst "$HOME/src/$path"
#    if [ -d $dst ]
#        cd "$dst"
#        return
#    end
#    mkdir -p "$dst"
#    and if git clone --recursive "https://github.com/$path" "$dst"
#        cd "$dst"
#    else
#        command rm -rf "$dst"
#    end
#end
#
#function gh
#    set -l branch (git rev-parse --abbrev-ref HEAD)
#    if [ ! "$branch" ]
#        return
#    end
#
#    # In case multiple PRs are using the same branch, open the first.
#    set -l url (hub pr list -f %U\n -h $branch)[1]
#
#    if [ ! "$url" ]
#        set url (hub browse -u)
#    end
#
#    open "$url"
#end


#function up
#    if [ -z "$argv" ]
#        cd ..
#        return
#    end
#
#    # Number.
#    if string match -qra '^\d+' "$argv"
#        up_n "$argv"
#        return
#    end
#
#    up_d "$argv"
#end
#
#function up_n
#    set -l count "$argv"
#    if [ -z "$count" ]
#        set count 1
#    end
#    cd (string join .. (string repeat -n $count ' /' | string split ' '))
#end
#
#function up_d
#    set -l pwd (string split --no-empty '/' $PWD)
#    # Reverse directories.
#    set -l pwd $pwd[-1..1]
#    # Skip current directory.
#    set -l pwd $pwd[2..-1]
#    for i in (seq (count $pwd))
#        if echo $pwd[$i] | rg -q $argv
#            up_n $i
#            return
#        end
#    end
#end
