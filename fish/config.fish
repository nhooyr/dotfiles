if status is-interactive
    tabs -4
end
set -gx LESS -RXF -ix4
set fish_greeting
fish_add_path --path ~/.local/bin
fish_add_path --path ~/.local/bin/dotfiles
fish_add_path --path /opt/homebrew/bin
set -gx MANPAGER nvim +Man!
set -gx EDITOR nvim
function abbrali --argument-names name
    abbr -a "$name" $argv[2..]
    alias "$name" "$argv[2..]"
end
abbrali vi nvim
abbr -a --command sudo vi nvim
abbr -a s sudo
alias sudo='sudo --preserve-env=TERM_PROGRAM --preserve-env=SSH_TTY'
fish_hybrid_key_bindings
set -gx GOPATH ~/.local/share/go

set -gx LSCOLORS \
    # dir
    ex \
    # symlink
    Gx \
    # socket
    Cx \
    # pipe
    Cx \
    # exec
    Fx \
    # block special
    Hc \
    # character special
    Hc \
    # setuid exec
    Hf \
    # setgid exec
    Hf \
    # directory writable to others, with sticky bit
    He \
    # directory writable to others, without sticky bit
    He \
    # dataless file
    ha
set -gx LSCOLORS "$(string join '' $LSCOLORS)"
alias l='ls --color -lhF'
alias ll='ls --color -lhAF'
alias r="source $__fish_config_dir/config.fish"
function multicd
    echo cd "$(string repeat -n "$(math "$(string length -- "$argv")" - 1)" ../)"
end
abbr --add dotdot --regex '^\.\.\.+$' --function multicd
function cdc --wraps cd --argument-names dir
    set -l prevd "$PWD"
    if cd "$dir"
        $argv[2..]
        set -l code "$status"
        cd -- "$prevd"
        return "$code"
    else
        return 1
    end
end
function cdf --wraps cd --argument-names file
    cd "$(dirname "$file")"
end
function up
    if not set -q argv[1]
        cd ..
        return
    end

    if string match --quiet --regex '^[0-9]+$' -- "$argv"
        set -l up (string repeat --count "$argv" ../)
        cd "./$up"
        return
    end

    set -l dir "$PWD"
    while test "$dir" != /
        set dir "$(path dirname -- "$dir")"
        if string match --quiet --regex -- "$argv" "$(path basename -- "$dir")"
            cd -- "$dir"
            return
        end
    end

    printf 'up: no parent dir matches %s\n' "$argv" >&2
    return 1
end
abbrali pd prevd
abbrali nd nextd
abbrali t time
abbrali mkd 'cd "$(mktemp -d)"'
alias sshq="ssh -O exit"
alias sshu="ssh -oControlPath=none"
abbrali socks ssh -ND1080

function colors
    for name in black red green yellow blue magenta cyan white
        printf '%s\t%s\n' "$(set_color "$name")$name" "$(set_color "br$name")br$name"
    end
end

abbrali g git
abbrali gsh git show
abbrali ga git add -A
abbrali gap git add -p
abbrali gp git push
abbrali gpf git push --force-with-lease
abbrali gcm git commit
abbrali gcma git commit --amend
abbrali gcmf git commit --fixup
abbrali grb git rebase
abbrali grbi git rebase -i
abbrali grbc git rebase --continue
abbrali grba git rebase --abort
abbrali gs git status
abbrali gd git diff
abbrali grt git reset
abbrali grth git reset --hard
abbrali gdc git diff --cached
abbrali grm git rm
abbrali grmr git rm -r
abbrali grmc git rm --cached
abbrali grmcr git rm --cached -r
abbrali gl git log
abbrali gls git ls-files
abbrali gcl git clone
abbrali gpl git pull
abbrali gro git remote -v
abbrali gb git branch
abbrali gst git stash push -u
abbrali gsts git stash show
abbrali gstsp git stash show -p
abbrali gstp git stash pop
abbrali gstl git stash list
abbrali gstd git stash drop

function gcd
    set -l git_root "$(git rev-parse --show-toplevel)"; or return 1
    cd "$git_root"
end

alias gg='git grep -iI'
alias grep='grep --color=auto -inI'
alias rg='rg -Sn'
alias fd='fd -HL'
function f
    find . -iname "*$argv*"
end
abbrali nl nlogin
abbrali np npass
abbrali ne nemail

abbrali chx chmod +x
alias ymp3='yt-dlp --audio-format mp3 -x --embed-thumbnail'
alias num='shuf -n1 -i 1-999'

function noti --wraps time
    time $argv
    set -l code "$status"
    printf '\a'
    return "$code"
end
abbrali n noti
abbr -a --command noti e eval

if status is-interactive
    fzf --fish | source
end
set -gx FZF_DEFAULT_OPTS "--style=minimal --layout=reverse --height=~50% --min-height=0 --cycle \
    --bind=ctrl-/:toggle-preview --no-mouse --scroll-off=0 --info=inline-right \
    --color=bw,query:regular,info:italic:underline,hl:underline:bold,fg+:regular:reverse,\
hl+:reverse:underline,pointer:magenta:bold"
# Display no prefix by default in history view.
set -gx FZF_CTRL_R_OPTS "--with-nth 3.. --bind 'alt-t:change-with-nth(2..|1,3..|3..)'"
function fzf_accept_and_run --argument-names widget
    set -l AQSNOW_FISH_RENDEZVOUS "$(mktemp)"

    set -l action "alt-enter:execute-silent(printf %s {+} > $(string escape -- "$AQSNOW_FISH_RENDEZVOUS"))+accept"
    set -l option "--bind=$(string escape -- "$action")"

    set -lx FZF_CTRL_R_OPTS "$FZF_CTRL_R_OPTS $option"
    set -lx FZF_CTRL_T_OPTS "$FZF_CTRL_T_OPTS $option"

    "$widget"

    if test -s "$AQSNOW_FISH_RENDEZVOUS"
        aqsnow_exec
    end
    rm "$AQSNOW_FISH_RENDEZVOUS"
end
function aqsnow_exec
    set -l cmd $(commandline --tokens-expanded)
    if test "$(count $cmd)" -eq 1 -a -f "$cmd[1]" && not type -q "$cmd[1]"
        if not string match -qr '^\.?/' -- "$cmd[1]"
            fish_commandline_prepend "$EDITOR"
        end
    end
    commandline -f execute
end
bind -M insert enter aqsnow_exec
bind -m insert enter aqsnow_exec
bind -M replace -m insert enter aqsnow_exec repaint-mode
function aqsnow_edit_command
    set -lx AQSNOW_FISH_RENDEZVOUS "$(mktemp)"
    edit_command_buffer
    if test -s "$AQSNOW_FISH_RENDEZVOUS"
        aqsnow_exec
    end
    rm "$AQSNOW_FISH_RENDEZVOUS"
end
for mode in default insert
    bind -M "$mode" ctrl-r 'fzf_accept_and_run fzf-history-widget'
    bind -M "$mode" ctrl-t 'fzf_accept_and_run fzf-file-widget'
    bind -M "$mode" alt-e aqsnow_edit_command
end

alias vsce='NO_COLOR=1 command vsce'

set -gx DOTFILES "$(realpath "$(realpath "$__fish_config_dir/config.fish")/../..")"
function add_cdpath
    for path in $argv
        if not contains "$path" $CDPATH
            set --append --path -g CDPATH "$path"
        end
    end
end
add_cdpath . ~ "$DOTFILES"
if test -f "$DOTFILES/secrets/fish/config.fish"
    source "$DOTFILES/secrets/fish/config.fish"
end
source "$DOTFILES/fish/prompt.fish"
source "$DOTFILES/fish/ghcl.fish"

if test "$PWD" = "$HOME"
    cd "$DOTFILES"
end
