if status is-interactive
    tabs -4
end
set -gx LESS -RXF -ix4
set -g fish_greeting
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
set -g fish_color_error normal --italic
set -g fish_color_quote green
set -g fish_color_search_match regular --reverse
set -g fish_pager_color_progress magenta --underline --italic
set -g fish_pager_color_prefix --italic --underline
set -g fish_pager_color_selected_prefix --bold --italic
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
set -gx LS_COLORS "di=34:ln=3;36:so=3;32:pi=3;32:ex=3;35:bd=3;37;42:\
cd=3;37;42:su=3;37;45:sg=3;37;45:tw=3;37;44:ow=3;37;44:st=34"
function ls
    if type -q gls
        gls --group-directories-first $argv
    else
        command $argv
    end
end
alias l='ls --color -lhF'
alias ll='ls --color -lhAF'
alias r="source $__fish_config_dir/config.fish"

abbrali t time
abbrali mkd 'cd "$(mktemp -d)"'
alias sshq="ssh -O exit"
alias sshu="ssh -oControlPath=none"
abbrali socks ssh -ND1080

function colors
    for name in black red green yellow blue magenta cyan white
        printf '%s\t%s\n' "$(set_color "$name")$name" "$(set_color "br$name")br$name"
    end
    set_color reset
end

fish_add_path --path /opt/homebrew/share/git-core/contrib/diff-highlight
abbrali g git
abbrali gsh git show
abbrali ga git add -A
abbrali gap git add -p
abbrali gp git push
abbrali gpf git push --force-with-lease
abbrali gcm git commit
alias gcp='gcm && gp'
alias gacp='ga && gcp'
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
abbrali grmf git rm -rf
abbrali grmc git rm --cached
abbrali grmcr git rm --cached -r
abbrali gl git log
abbrali glsf git ls-files
abbrali gcl git clone
abbrali gpl git pull
abbrali gro git remote -v
abbrali gb git branch -vv
abbrali gba git branch -avv
abbrali gbr git branch -rvv
abbrali gst git stash push -u
abbrali gsts git stash show
abbrali gstsp git stash show -p
abbrali gstp git stash pop
abbrali gstl git stash list
abbrali gstd git stash drop
abbrali gbl git blame

function gcd
    set -l git_root "$(git rev-parse --show-toplevel)"; or return 1
    cd "$git_root"
end

function grep
    if type -q ggrep
        ggrep --color -inIE $argv
    else
        command grep --color -inIE $argv
    end
end
alias gg='git grep -iI'
set -gx GREP_COLORS 'mt=03;37;44:fn=36:ln=03:bn=03:se=00'
set -gx GREP_COLOR '03;37;44'
alias rg="rg -Sn --no-heading \
    --colors=path:fg:cyan \
    --colors=line:none \
    --colors=line:style:italic \
    --colors=match:none \
    --colors=match:fg:white \
    --colors=match:bg:blue \
    --colors=match:style:italic \
"
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
    --color=bw,query:regular,info:italic:underline,hl:underline:italic,fg+:regular:reverse,\
hl+:reverse:italic,pointer:magenta:bold"
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
source "$DOTFILES/fish/github.fish"

if status is-interactive
    source "$DOTFILES/fish/prompt.fish"
    source "$DOTFILES/fish/cd.fish"
    if test "$PWD" = "$HOME"
        cd "$DOTFILES"
    end
end
