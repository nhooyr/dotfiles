if not set -q HOMEBREW_PREFIX
    /opt/homebrew/bin/brew shellenv fish | source
end
set -gx GOPATH ~/.local/share/go
fish_add_path --prepend --move --path ~/.local/bin/dotfiles \
    ~/.local/bin \
    /opt/homebrew/share/git-core/contrib/diff-highlight \
    "$GOPATH/bin" \
    /opt/homebrew/bin
if not status is-interactive
    return 0
end

tabs -4
set -gx LESS -RXF -ix4
set -g fish_greeting
set -gx MANPAGER nvim +Man!
set -gx EDITOR nvim
function abbrali --argument-names name
    abbr -a "$name" $argv[2..]
    alias "$name" "$argv[2..]"
end
abbrali vi nvim
abbr -a --command sudo vi nvim
abbrali s sudo
alias sudo='sudo --preserve-env=SSH_TTY'
abbr -a --position anywhere '$pbp' '"$(pbpaste)"'
abbrali pbp pbpaste
fish_hybrid_key_bindings
set -g fish_color_error normal --italic
set -g fish_color_quote green
set -g fish_color_search_match normal --reverse
set -g fish_pager_color_progress magenta --underline --italic
set -g fish_pager_color_prefix --italic --underline
set -g fish_pager_color_selected_background --background=black
set -g fish_pager_color_selected_prefix white --bold --italic
set -g fish_pager_color_selected_completion white
set -g fish_pager_color_selected_description white
function r
    source "$__fish_config_dir/config.fish"
end

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
        command ls $argv
    end
end
alias l='ls --color -lhF'
alias ll='ls --color -lhAF'
abbr -a fd fd -HL
function f
    find . -iname "*$argv*"
end
set -gx GREP_COLORS 'mt=03;37;44:fn=36:ln=03:bn=03:se=00'
set -gx GREP_COLOR '03;37;44'
abbr -a grep gre
function gre
    if type -q ggrep
        ggrep --color -inIE $argv
    else
        command grep --color -inIE $argv
    end
end

abbrali t time
abbrali mkd 'cd "$(mktemp -d)"'
abbrali sshq ssh -O exit
abbrali sshu ssh -oControlPath=none
abbrali socks ssh -ND1080
abbrali py python3

function colors
    for name in black red green yellow blue magenta cyan white
        printf '%s\t%s\n' "$(set_color "$name")$name" "$(set_color "br$name")br$name"
    end
    set_color reset
end

abbrali nl nlogin
abbrali np npass
abbrali ne nemail

abbrali chx chmod +x
abbrali ymp3 yt-dlp --audio-format mp3 -x --embed-thumbnail
abbrali num random 1 999

function noti --wraps time
    time $argv
    set -l code "$status"
    printf '\a'
    return "$code"
end
abbrali n noti
abbr -a --command noti e eval

fzf --fish | source
set -gx FZF_DEFAULT_OPTS "--style=minimal --layout=reverse --height=~50% --min-height=0 --cycle \
    --bind=ctrl-/:toggle-preview --no-mouse --scroll-off=0 --info=inline-right \
    --color=bw,query:regular,info:italic:underline,hl:underline:italic,fg+:regular:reverse,\
hl+:reverse:italic,pointer:magenta:bold"
# Display no prefix by default in history view.
set -gx FZF_CTRL_R_OPTS "--with-nth 3.. --bind 'alt-t:change-with-nth(2..|1,3..|3..)'"
function fzf_accept_and_run --argument-names widget
    set -l action "alt-enter:execute-silent(printf %s {+} > $(string escape -- "$AQSNOW_FISH_RENDEZVOUS"))+accept"
    set -l option "--bind=$(string escape -- "$action")"

    set -lx FZF_CTRL_R_OPTS "$FZF_CTRL_R_OPTS $option"
    set -lx FZF_CTRL_T_OPTS "$FZF_CTRL_T_OPTS $option"

    $widget
    aqsnow_rendezvous
end
function aqsnow_exec
    set -l cmd $(commandline --current-process --tokens-expanded)
    if test "$(count $cmd)" -eq 1 && test -f "$cmd[1]" && not type -q -- "$cmd[1]" && not string match -qr '^\.?/' -- "$cmd[1]"
        fish_commandline_prepend "$EDITOR --"
    end
    commandline -f execute
end
function aqsnow_rendezvous
    test -s "$AQSNOW_FISH_RENDEZVOUS"; or return 0
    aqsnow_nvim_fzf_file_widget; and return 0
    rm "$AQSNOW_FISH_RENDEZVOUS"
    aqsnow_exec
    set -g fish_bind_mode insert
end
if not set -q __aqsnow_rendezvous_dir
    set -l rendezvous_dir "$(mktemp -d)"; or return
    set -g __aqsnow_rendezvous_dir "$rendezvous_dir"
    set -gx AQSNOW_FISH_RENDEZVOUS "$rendezvous_dir/rendezvous"
    function aqsnow_rm_rendezvous --on-event fish_exit --inherit-variable rendezvous_dir
        rm -rf -- "$rendezvous_dir"
    end
end
function aqsnow_nvim_fzf_file_widget
    if ! grep -qF '<M-v>' "$AQSNOW_FISH_RENDEZVOUS"
        return 1
    end
    rm "$AQSNOW_FISH_RENDEZVOUS"
    fzf_accept_and_run fzf-file-widget
end
function aqsnow_postexec --on-event fish_postexec --argument-names cmdline
    set -l code "$status"
    test -s "$AQSNOW_FISH_RENDEZVOUS"; or return 0
    aqsnow_nvim_fzf_file_widget; and return 0
    rm "$AQSNOW_FISH_RENDEZVOUS"
    test "$code" -eq 0; or return 0

    switch "$cmdline"
        case 'git commit --amend*' '* git commit --amend'
            gpf
        case 'git commit*' '* git commit'
            git push
    end
end
bind -M default -m insert enter aqsnow_exec
bind -M insert enter aqsnow_exec
bind -M default -m insert alt-enter accept-autosuggestion aqsnow_exec
bind -M insert alt-enter accept-autosuggestion aqsnow_exec
for mode in default insert
    bind -M "$mode" ctrl-r 'fzf_accept_and_run fzf-history-widget'
    bind -M "$mode" ctrl-t 'fzf_accept_and_run fzf-file-widget'
    bind -M "$mode" alt-v 'fzf_accept_and_run fzf-file-widget'
    bind -M "$mode" alt-e edit_command_buffer aqsnow_rendezvous
end

abbrali vsce NO_COLOR=1 command vsce

set -gx DOTFILES "$(path resolve "$__fish_config_dir/config.fish/../..")"
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
source "$DOTFILES/fish/git.fish"
source "$DOTFILES/fish/github.fish"

source "$DOTFILES/fish/prompt.fish"
source "$DOTFILES/fish/cd.fish"
if test "$PWD" = "$HOME"
    cd "$DOTFILES"
end
