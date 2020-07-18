if not status --is-interactive
    exit 0
end

set -U fish_greeting

set -U fish_color_search_match --background=bad6fe
set -U fish_pager_color_description 581D5B
set -U fish_pager_color_prefix --bold black
set -U fish_pager_color_progress brwhite --background=af005f
set -U fish_color_autosuggestion 555
set -U fish_color_error red

set -gx EDITOR 'editor'
set -gx MANWIDTH 80
set -gx MANPAGER 'ansifilter | pager'
set -gx PATH ~/.local/bin $PATH
if test (hostname) = aubble
    set -gx PATH /snap/bin $PATH
end

set -gx GOPATH ~/Programming/gopath
set -gx PATH $GOPATH/bin $PATH
set -gx PATH /usr/local/opt/ruby/bin /usr/local/lib/ruby/gems/2.6.0/bin $PATH

set -g fish_prompt_pwd_dir_length 0

# Occasionally things give me errors because the default limit is so low.
ulimit -n 8192

abbr --add --global b brew
abbr --add --global bc brew cask
abbr --add --global bin brew install
abbr --add --global bcin brew cask install
abbr --add --global bif brew info
abbr --add --global bcif brew cask info
abbr --add --global br brew remove
abbr --add --global bcr brew cask remove
abbr --add --global bu brew update\; and brew upgrade\; and brew cask upgrade
abbr --add --global bs brew search
abbr --add --global ct cat

abbr --add --global g git
abbr --add --global gi git init
abbr --add --global gch git checkout
abbr --add --global ga git add
abbr --add --global gcm git commit -v
abbr --add --global gcma git commit -v --amend
abbr --add --global gcmf git commit -v --fixup
abbr --add --global gb git branch
abbr --add --global grt git reset
abbr --add --global grh git reset --hard
abbr --add --global grb git rebase
abbr --add --global gpl git pull
abbr --add --global gf git fetch
abbr --add --global gps git push
abbr --add --global gpf git push -f
abbr --add --global gs git status
abbr --add --global gst git stash
abbr --add --global gstp git stash pop
abbr --add --global gsh git show
abbr --add --global gd git diff
abbr --add --global gdc git diff --cached
abbr --add --global gl git log
abbr --add --global gll git_log_line
abbr --add --global gpr git pull-request
abbr --add --global gm git merge
abbr --add --global gcl git clone
abbr --add --global grv git revert
abbr --add --global gro git remote
abbr --add --global grm git rm
abbr --add --global gcp git cherry-pick
abbr --add --global gyn hub sync
abbr --add --global gcr git codereview
abbr --add --global gis git issue

abbr --add --global md mkdir -p

abbr --add --global r source ~/.config/fish/config.fish $argv

abbr --add --global ec e ~/.config/fish/config.fish

abbr --add --global l ls -lh
abbr --add --global ll ls -lhA

abbr --add --global d cd
abbr --add --global pd prevd
abbr --add --global nd nextd

abbr --add --global m man

abbr --add --global gh github
abbr --add --global pc pbcopy
abbr --add --global pp pbpaste

abbr --add --global gpprof go tool pprof
abbr --add --global c clear
abbr --add --global k kubectl

set -g CDPATH . \
    ~ \
    ~/Programming \
    ~/Programming/github \
    ~/Programming/forks \
    ~/Programming/coder \
    ~/Programming/coder/go \
    ~/Programming/coder/go/m/lib \
    ~/Programming/coder/go/m/srv \
    ~/Programming/scratch \
    ~/.config \
    ~/.config/fish \
    ~/.local

# The next line updates PATH for the Google Cloud SDK.
if [ -f /usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.fish.inc ]
    source /usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.fish.inc
end
