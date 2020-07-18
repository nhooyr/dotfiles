if not status --is-interactive
    exit 0
end

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

# Fish expects this to be a command so we cannot directly use 'subl -wn'
# Plus the considerations for linux.
set -gx EDITOR "$HOME/src/nhooyr/dotfiles/bin/editor"
set -gx PAGER less
set -gx MANPAGER manpager
set -gx MANWIDTH 80
set -gx GOPATH ~/.local/share/gopath
set -gx GOPRIVATE go.coder.com

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
addToPath (yarn global bin)

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
abbr -ag c clear

abbr -ag g git
abbr -ag gch git checkout
abbr -ag ga git add
abbr -ag gaa gitAddAll
abbr -ag gcm git commit -v
abbr -ag gcma git commit -v --amend
abbr -ag gcmf git commit -v --fixup
abbr -ag gb git branch
abbr -ag grt git reset
abbr -ag grb git rebase
abbr -ag gpl git pull
abbr -ag gf git fetch
abbr -ag gps git push -u
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
abbr -ag v nvim
abbr -ag d cd
abbr -ag mt mutagen

alias r="source ~/.config/fish/config.fish"
alias e="env SUBLIME_PERSISTENT=1 $EDITOR"
alias grep="grep --color"
alias l="ls -lh"
alias ll="ls -lhA"
alias pd=prevd
alias nd=nextd
alias npm="echo use yarn pls"
alias xnpm="command npm"
alias git="hub"
alias ec="e ~/.config/fish/config.fish"
# alias ed="e ~/src/nhooyr/dotfiles/home.sublime-project"
alias first_non_fixup="git log --pretty='%H' -1 --invert-grep --grep 'fixup! '"
# alias rg="rg -S"
alias h="history merge"

set -gx BAT_THEME GitHub
alias cat="bat"

function fcm
    gitAddAll
    git commit --amend --no-edit
    git push -f
end

function gitAddAll
    set -l files * .*
    git add -u $files
end

function ghd
    set -l path $argv[1]
    set -l path (string replace -r ".*://" "" "$path")
    set -l path (string replace "github.com/" "" "$path")
    set -l path (string split / "$path")
    set -l path (string join / $path[1..2])
    if [ -z $path ]
        echo "invalid URL or path"
        return
    end

    set -l dst "$HOME/src/$path"
    if [ -d $dst ]
        cd "$dst"
        return
    end
    mkdir -p "$dst"
    and if git clone --recursive "https://github.com/$path" "$dst"
        cd "$dst"
    else
        command rm -rf "$dst"
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

    if [ (uname) = Darwin ]
        python -mwebbrowser "$url" >/dev/null
    else if [ "$hostname" = dev ]
        ssh ien "osascript -e 'tell application \"Safari\" to activate'"
        and \
            ssh ien open "$url"
    else
        echo "$url"
    end
end

function lolsay
    cowsay -f (ls  /usr/local/share/cows | cut -f 10 | gshuf | head -n 1) (fortune -o) | lolcat $argv
end

if [ (uname) = Darwin ]
    source /usr/local/opt/fzf/shell/key-bindings.fish

    alias ls="gls --indicator-style=classify --color=auto"
    alias gol=goland
    alias sed=gsed

    abbr -ag b brew
    function cdr
        if echo "$PWD" | grep -q $HOME
            set -l dir (string replace /Users/nhooyr \~ $PWD)
            ssh -t dev.coder.com "cd $dir 2> /dev/null; exec \$SHELL -l"
        else
            ssh dev.coder.com
        end
    end

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

    function fp
        mutagen forward create tcp:127.0.0.1:$argv[1] dev2.coder.com:tcp:127.0.0.1:$argv[1]
    end
end

if [ (uname) = Linux ]
    alias ls="ls --indicator-style=classify --color=auto"
    alias pc="ssh ien pbcopy"
    alias pp="ssh ien pbpaste"
    alias noti="ssh ien noti"

    abbr -ag ien ssh ien
    abbr -ag b yay

    function gol
        ssh ien "osascript -e 'tell application \"Goland\" to activate'"
        set -l path (realpath "$argv")
        if not string match -q "$HOME/src/*" "$path"
            echo "Must be within ~/src"
            return 1
        end
        set path (string replace ~ /Users/nhooyr "$path")
        ssh ien goland "$path"
    end

    addToPath ~/src/nhooyr/dotfiles/linuxBin

    addToPath /home/nhooyr/src/emscripten-core/emsdk
    addToPath /home/nhooyr/src/emscripten-core/emsdk/fastcomp/emscripten
    addToPath /home/nhooyr/src/emscripten-core/emsdk/node/12.9.1_64bit/bin

    set -gx EMSDK /home/nhooyr/src/emscripten-core/emsdk
    set -gx EM_CONFIG /home/nhooyr/.emscripten
    set -gx EMSDK_NODE /home/nhooyr/src/emscripten-core/emsdk/node/12.9.1_64bit/bin/node
end

fzf_key_bindings
function fzf-paths
    set -l prevCmdline (commandline -b)
    set -l result (paths | fzf --height 40% --query (commandline -t))
    set -l realPath (string replace '~' ~ "$result")
    if [ -n "$prevCmdline" ]
        commandline -t -- "$result"
        commandline -f repaint
        return
    end
    if [ -d $realPath ]
        commandline -t -- "cd $result"
        commandline -f execute
    else if [ -e $realPath ]
        commandline -t -- "e $result"
        commandline -f execute
    else
        echo "$result does not exist"
        commandline -f repaint
    end
end
bind \ee fzf-paths
bind \cv accept-autosuggestion execute
