if not status --is-interactive
    exit 0
end

tabs -2
# https://superuser.com/questions/1067801/ctrlr-in-shell-if-i-go-past-the-command-i-want-how-do-i-get-back-to-it
stty -ixon
# Occasionally things give me errors because the default limit is so low.
ulimit -n 16384

set -U fish_greeting
set -U fish_color_command normal
set -U fish_color_quote normal
set -U fish_color_redirection af005f
set -U fish_color_end af005f
set -U fish_color_error normal
set -U fish_color_param normal
set -U fish_color_comment 555
# set -U fish_color_match
# set -U fish_color_selection
set -U fish_color_search_match --background=bad6fe
set -U fish_color_operator af005f
set -U fish_color_escape af005f
# set -g fish_color_cwd
set -U fish_color_autosuggestion 555
# set -g fish_color_user
# set -g fish_color_host
# set -g fish_color_cancel

set -U fish_pager_color_prefix --bold black
# set -g fish_pager_color_completion
set -U fish_pager_color_description af005f
set -U fish_pager_color_progress 581D5B
# set -g fish_pager_color_secondary

alias is_darwin="[ (uname) = Darwin ]"
alias is_linux="[ (uname) = Linux ]"
# Fish expects this to be a command so we cannot directly use 'subl -wn'
# Plus the considerations for linux.
set -gx EDITOR "$HOME/src/nhooyr/dotfiles/bin/editor"
set -gx PAGER "ansifilter | $EDITOR"
set -gx MANWIDTH 80
set -gx GOPATH ~/.local/share/gopath

function addToPath
    if echo $PATH | grep -q "$argv"
        # Already in path.
        return
    end
    set -gx PATH "$argv" $PATH
end

addToPath ~/.local/bin
addToPath "$GOPATH/bin"
addToPath /usr/local/sbin
addToPath /usr/local/opt/ruby/bin
addToPath /usr/local/lib/ruby/gems/2.6.0/bin
addToPath ~/src/nhooyr/dotfiles/bin

if [ -f /usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.fish.inc ]
    source /usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.fish.inc
end

set -g CDPATH . \
    ~/src/nhooyr/dotfiles \
    ~/src/nhooyr \
    ~/src/cdr \
    ~/src/codercom \
    ~/src/play \
    ~/src \
    ~/.config

set -gx FZF_DEFAULT_OPTS "--color light,bg+:153,fg+:-1,pointer:-1,prompt:-1,hl:125,hl+:125,info:-1,spinner:-1 --tabstop=4"

set -l RESET_LS_COLORS 'rs=00:di=00:ln=00:mh=00:pi=00:so=00:do=00:bd=00:cd=00:or=00:mi=00:su=00:sg=00:ca=00:tw=00:ow=00:st=00:ex=00:*.tar=00:*.tgz=00:*.arc=00:*.arj=00:*.taz=00:*.lha=00:*.lz4=00:*.lzh=00:*.lzma=00:*.tlz=00:*.txz=00:*.tzo=00:*.t7z=00:*.zip=00:*.z=00:*.dz=00:*.gz=00:*.lrz=00:*.lz=00:*.lzo=00:*.xz=00:*.zst=00:*.tzst=00:*.bz2=00:*.bz=00:*.tbz=00:*.tbz2=00:*.tz=00:*.deb=00:*.rpm=00:*.jar=00:*.war=00:*.ear=00:*.sar=00:*.rar=00:*.alz=00:*.ace=00:*.zoo=00:*.cpio=00:*.7z=00:*.rz=00:*.cab=00:*.wim=00:*.swm=00:*.dwm=00:*.esd=00:*.jpg=00:*.jpeg=00:*.mjpg=00:*.mjpeg=00:*.gif=00:*.bmp=00:*.pbm=00:*.pgm=00:*.ppm=00:*.tga=00:*.xbm=00:*.xpm=00:*.tif=00:*.tiff=00:*.png=00:*.svg=00:*.svgz=00:*.mng=00:*.pcx=00:*.mov=00:*.mpg=00:*.mpeg=00:*.m2v=00:*.mkv=00:*.webm=00:*.ogm=00:*.mp4=00:*.m4v=00:*.mp4v=00:*.vob=00:*.qt=00:*.nuv=00:*.wmv=00:*.asf=00:*.rm=00:*.rmvb=00:*.flc=00:*.avi=00:*.fli=00:*.flv=00:*.gl=00:*.dl=00:*.xcf=00:*.xwd=00:*.yuv=00:*.cgm=00:*.emf=00:*.ogv=00:*.ogx=00:*.aac=00:*.au=00:*.flac=00:*.m4a=00:*.mid=00:*.midi=00:*.mka=00:*.mp3=00:*.mpc=00:*.ogg=00:*.ra=00:*.wav=00:*.oga=00:*.opus=00:*.spx=00:*.xspf=00:'
set -l MY_LS_COLORS "di=34:ln=35:so=32:pi=32:ex=31;01"
set -gx LS_COLORS "$RESET_LS_COLORS:$MY_LS_COLORS"

abbr -ag - cd -
abbr -ag vim nvim
abbr -ag md mkdir -p
abbr -ag m man

abbr -ag g git
abbr -ag gch git checkout
abbr -ag ga git add
abbr -ag gaa git add \* .\*
abbr -ag gcm git commit -v
abbr -ag gcma git commit -v --amend
abbr -ag gcmf git commit -v --fixup
abbr -ag gb git branch
abbr -ag grt git reset
abbr -ag grb git rebase
abbr -ag gpl git pull
abbr -ag gf git fetch
abbr -ag gps git push
abbr -ag gpf git push -f
abbr -ag gs git status
abbr -ag gst git stash
abbr -ag gsh git show
abbr -ag gd git diff
abbr -ag gdc git diff --cached
abbr -ag gl git log
abbr -ag gpr git pull-request
abbr -ag gcl git clone
abbr -ag grv git revert
abbr -ag gro git remote
abbr -ag grm git rm
abbr -ag gcp git cherry-pick
abbr -ag gm git merge
abbr -ag k kubectl
abbr -ag y yarn
abbr -ag f functions
abbr -ag s sudo
abbr -ag n noti
abbr -ag d cd

alias r="source ~/.config/fish/config.fish"
alias e="$EDITOR"
alias grep="grep --color"
if is_darwin
    alias ls="gls --indicator-style=classify --color=auto"
else
    alias ls="ls --indicator-style=classify --color=auto"
end
alias l="ls -lh"
alias ll="ls -lhA"
alias pd=prevd
alias nd=nextd
alias npm="echo use yarn pls"
alias xnpm="command npm"
alias git="hub"
alias ec="e ~/.config/fish/config.fish"
alias first_non_fixup="git log --pretty='%H' -1 --invert-grep --grep 'fixup! '"
alias rg="rg -S"
alias h="history merge"
alias fcm="git add * .*; git commit --amend --no-edit; git push -f"

function ghd
    mkdir -p "$HOME/src/$argv[1]"
    and git clone --recursive "https://github.com/$argv[1]" "$HOME/src/$argv[1]"
    and cd "$HOME/src/$argv[1]"
end

if is_linux
    abbr -ag ien ssh ien
    alias pc="ssh ien pbcopy"
    alias pp="ssh ien pbpaste"
end

if is_darwin
    alias gol="goland"

    abbr -ag b brew
    abbr -ag cdr ssh dev.coder.com
    
    function startcdr
        gcloud --configuration=nhooyr-coder compute instances start dev
    end

    function stopcdr
        ssh dev.coder.com sudo poweroff
    end
    
    alias pc=pbcopy
    alias pp=pbpaste
    alias icloud="cd ~/Library/Mobile\ Documents/com~apple~CloudDocs"

    alias bu="brew update && brew upgrade && brew cask upgrade"
    alias noti='noti --message "You wanted a notification" --title Terminal'
    alias rm=tra

    function tra
        for file in $argv
            set -l file (realpath "$file")
            osascript -e "tell application \"Finder\" to delete POSIX file \"$file\"" >/dev/null
        end
    end

    function flushdns
        sudo killall -HUP mDNSResponder
        sudo killall mDNSResponderHelper
        sudo dscacheutil -flushcache
    end
end

function mcd
    mkdir -p $argv
    cd $argv
end

function cdp
    for cdpath in $CDPATH
        if [ -e "$cdpath/$argv" ]
            echo "$cdpath/$argv"
            return
        end
    end
end

function gcd
    set -l gcd (git rev-parse --show-toplevel)
    if [ "$status" -eq 0 ]
        cd "$gcd"
    end
end

function gh
    set -l branch (git rev-parse --abbrev-ref HEAD)
    if [ ! "$branch" ]
        return
    end

    # In case multiple PRs are using the same branch, open the first.
    set -l url (hub pr list -f %U\n -h $branch)[1]

    if [ ! "$url" ]
        set url (hub browse -u)
    end

    python -mwebbrowser "$url" >/dev/null
end

function lolsay
    cowsay -f (ls  /usr/local/share/cows | cut -f 10 | gshuf | head -n 1) (fortune -o) | lolcat $argv
end

fzf_key_bindings
function fzf-cdpath
    set -l result (find -L $CDPATH[2..-1] -depth 1 -prune -type d -print 2> /dev/null | fzf --height 40% --query (commandline -t))
    if [ $result ]
        commandline -t -- "$result"
    end
    commandline -f repaint
end
bind \ec fzf-cdpath
