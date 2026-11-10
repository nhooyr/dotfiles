if not set -q HOMEBREW_PREFIX
    /opt/homebrew/bin/brew shellenv fish | source
end
set -gx GOPATH ~/.local/share/go
fish_add_path --prepend --move --path ~/.local/bin/dotfiles \
    ~/.local/bin \
    /opt/homebrew/share/git-core/contrib/diff-highlight \
    "$GOPATH/bin" \
    /opt/homebrew/share/google-cloud-sdk/bin \
    /opt/homebrew/bin
if not status is-interactive
    return 0
end

tabs -4
set -gx LESS -RXF -ix4 --use-color -DBK -DCK -DEms -DMcd -DNcd -DPks -DRKs -DSbws
set -g fish_greeting
set -gx MANPAGER nvim +Man!
set -gx EDITOR nvim
function abbrali --argument-names name
    abbr -a "$name" $argv[2..]
    alias "$name" "$argv[2..]"
end
abbrali vi nvim
abbrali vim nvim
abbr -a --command sudo vi nvim
abbr -a --command sudo vim nvim
abbrali s sudo
alias sudo='sudo --preserve-env=SSH_TTY'
abbr -a --position anywhere '$pbp' '"$(pbpaste)"'
abbrali pbp pbpaste
fish_hybrid_key_bindings
set -g fish_color_error normal
set -g fish_color_quote green
set -g fish_color_search_match normal --reverse
set -g fish_color_selection white --background=black
set -g fish_pager_color_progress cyan --underline --italic
set -g fish_pager_color_description cyan --italic
set -g fish_pager_color_prefix --underline
set -g fish_pager_color_selected_background --background=black
set -g fish_pager_color_selected_prefix white --underline --bold
set -g fish_pager_color_selected_completion white
set -g fish_pager_color_selected_description white
function r
    source "$__fish_config_dir/config.fish"
end

set -gx LSCOLORS \
    # dir
    ex \
    # symlink
    gx \
    # socket
    cx \
    # pipe
    cx \
    # exec
    fx \
    # block special
    hc \
    # character special
    hc \
    # setuid exec
    hf \
    # setgid exec
    hf \
    # directory writable to others, with sticky bit
    he \
    # directory writable to others, without sticky bit
    he \
    # dataless file
    ha
set -gx LSCOLORS "$(string join '' $LSCOLORS)"
set -gx LS_COLORS "di=34:ln=36:so=32:pi=32:ex=35:bd=37;42:\
cd=37;42:su=37;45:sg=37;45:tw=37;44:ow=37;44:st=34"
function ls
    if command -q gls
        command gls --group-directories-first $argv
    else
        command ls $argv
    end
end
alias l='ls --color -lhF'
alias ll='ls --color -lhAF'
abbr -a fd fd -HLE .git
abbr -a bfs bfs -L -exclude -name .git
function f
    find . -iname "*$argv*"
end
set -gx GREP_COLORS 'mt=37;44:fn=36:ln=35:bn=35:se=00'
set -gx GREP_COLOR '37;44'
abbrali gre _grep -E
abbrali grf _grep -F
abbrali grer _grep -ER
abbrali grfr _grep -FR
function _grep --wraps 'grep --color -inI'
    if type -q ggrep
        ggrep --color -inI $argv
    else
        grep --color -inI -SE $argv
    end
end
abbrali ws gg "'[[:space:]]+\$'"

abbrali o open
abbrali e nvim
abbrali ec e '"$dotfiles/fish/config.fish"'
abbrali ei e '"$dotfiles/nvim/init.vim"'
abbrali t time
abbrali m math
function man
    command man $argv 2>/dev/null
end
abbrali to touch
abbrali sshak ssh-add --apple-load-keychain
set -q TMPDIR; or set -gx TMPDIR "$(mktemp -d)"
if not test -f "$TMPDIR/__aqsnow_ssh_keychain_loaded"
    sshak -q; and touch "$TMPDIR/__aqsnow_ssh_keychain_loaded"
end
abbrali sshq ssh -O exit
abbrali sshu ssh -oControlPath=none
abbrali ssha ssh-add
abbrali socks ssh -ND1080
abbrali py python3
function pyc --wraps 'python3 -c'
    python3 -c "print($argv)"
end
abbrali b brew
abbrali bi brew install
abbrali bu brew upgrade
abbrali bcl brew cleanup
abbrali tm tmux
abbrali tml tmux list-sessions
abbrali tma tmux attach-session
abbrali tmq tmux kill-server
abbrali tmk tmux kill-server
abbr -a --command tmux l list-sessions
abbr -a --command tmux a attach-session
abbr -a --command tmux k kill-server
abbr -a --command tmux q kill-server

function colors
    for name in black red green yellow blue magenta cyan white
        printf '%s\t%s\n' "$(set_color "$name")$name" "$(set_color "br$name")br$name"
    end
    set_color reset
end

abbrali nlo nlogin
abbrali npw npass
abbrali nem nemail

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
abbrali bell printf '\a'

fzf --fish | source
set -gx FZF_DEFAULT_OPTS "--style=minimal --layout=reverse --height=~50% --min-height=0 --cycle \
    --bind=ctrl-/:toggle-preview --bind=ctrl-s:toggle-sort --no-mouse --scroll-off=0 --info=inline-right \
    --color=bw,query:regular,info:italic,hl:underline,fg+:regular:reverse,\
hl+:reverse:underline,pointer:magenta:bold"
set -gx FZF_ALT_C_OPTS --bind=alt-enter:accept
# Display no prefix by default in history view.
set -gx FZF_CTRL_R_OPTS "--with-nth 3.. --bind 'alt-t:change-with-nth(2..|1,3..|3..)'"
function fzf_accept_and_run --argument-names widget
    set -l action "alt-enter:execute-silent(printf %s {+} > $(string escape -- "$AQSNOW_FISH_RENDEZVOUS"))+accept"
    set -l option "--bind=$(string escape -- "$action")"

    set -lx FZF_CTRL_R_OPTS "$FZF_CTRL_R_OPTS $option"
    set -lx FZF_CTRL_T_OPTS "$FZF_CTRL_T_OPTS $option"
    set -lx FZF_COMPLETION_OPTS "$FZF_COMPLETION_OPTS $option"
    set -lx FZF_EXPANSION_OPTS "$FZF_EXPANSION_OPTS $option"

    switch "$widget"
        case fzf-file-widget
            if test -z "$(commandline --cut-at-cursor --current-process --tokens-expanded)"
                and string match -q './*' -- "$(commandline --current-token --tokens-expanded)"
                set -l dir "$(string unescape -- "$(__fzf_parse_commandline)[1]")"
                if test "$dir" != .; and not string match -q './*' -- "$dir"
                    set dir "./$dir"
                end

                set -fx FZF_CTRL_T_COMMAND "find -L $(string escape -- "$dir") -mindepth 1 \
                    -name .git -prune -o -name node_modules -prune -o -print0 \
                    | path filter -zZ -fdx"
                set -fx FZF_CTRL_T_OPTS "$FZF_CTRL_T_OPTS --read0"
            end
    end
    $widget
    aqsnow_rendezvous
end
for mode in default insert
    bind -M "$mode" ctrl-r 'fzf_accept_and_run fzf-history-widget'
    bind -M "$mode" ctrl-t 'fzf_accept_and_run fzf-file-widget'
    bind -M "$mode" alt-v 'fzf_accept_and_run fzf-file-widget'
    bind -M "$mode" shift-tab 'fzf_accept_and_run fzf_complete'
    bind -M "$mode" alt-e edit_command_buffer aqsnow_rendezvous
end

function aqsnow_exec
    set -l cmd $(commandline --current-process --tokens-expanded)
    if test "$(count $cmd)" -eq 1; and test -f "$cmd[1]"; and not string match -qr '^\.{0,2}/' -- "$cmd[1]"
        if type -q -- "$cmd[1]"
            if test -x "$cmd[1]"; and file -bI -- "$cmd[1]" | grep -q "^text/"
                fish_commandline_prepend "$EDITOR --"
            end
        else
            fish_commandline_prepend "$EDITOR --"
        end
    end
    commandline -f execute
end
bind -M default -m insert enter aqsnow_exec
bind -M insert enter aqsnow_exec
bind -M default -m insert alt-enter accept-autosuggestion aqsnow_exec
bind -M insert alt-enter accept-autosuggestion aqsnow_exec

if not set -q __aqsnow_rendezvous_dir
    set -l rendezvous_dir "$(mktemp -d)"; or return
    set -g __aqsnow_rendezvous_dir "$rendezvous_dir"
    set -gx AQSNOW_FISH_RENDEZVOUS "$rendezvous_dir/rendezvous"
    function aqsnow_rm_rendezvous --on-event fish_exit --inherit-variable rendezvous_dir
        rm -rf -- "$rendezvous_dir"
    end
end
function aqsnow_run_requested
    test -s "$AQSNOW_FISH_RENDEZVOUS"; or return 1
    if not echo '<M-v>' | cmp -s - "$AQSNOW_FISH_RENDEZVOUS"
        rm "$AQSNOW_FISH_RENDEZVOUS"
        return 0
    end
    rm "$AQSNOW_FISH_RENDEZVOUS"
    fzf_accept_and_run fzf-file-widget
    return 1
end
function aqsnow_rendezvous
    aqsnow_run_requested; or return 0
    aqsnow_exec
    set -g fish_bind_mode insert
end
function aqsnow_postexec --on-event fish_postexec --argument-names cmdline
    set -l code "$status"
    if test "$code" -ne 0
        printf '\a'
    else if contains -- "$TERM_PROGRAM" Apple_Terminal tmux
        if test "$CMD_DURATION" -gt 4000; and set -l focused_tty "$(osascript -e 'tell application "Terminal"
            if frontmost then return tty of selected tab of front window
                return ""
            end tell')"
            if test "$TERM_PROGRAM" = tmux
                if not contains -- "$focused_tty $TMUX_PANE" $(tmux list-clients -F '#{client_tty} #{pane_id}')
                    printf '\a'
                end
            else if test "$focused_tty" != "$(tty)"
                printf '\a'
            end
        end
    end
    aqsnow_run_requested; or return 0
    test "$code" -eq 0; or return 0

    switch "$cmdline"
        case 'git commit --amend*' '* git commit --amend' 'gcma*' '* gcma'
            gpf
        case 'git commit*' '* git commit' 'gcm*' '* gcm'
            git push
    end
end

abbrali vsce NO_COLOR=1 command vsce
abbrali bun NO_COLOR=1 command bun
if test -f ~/.codex/config.toml; and test "$(yq '.tui.theme' ~/.codex/config.toml)" != "ansi"
    yq -i '.tui.theme = "ansi"' ~/.codex/config.toml
end
abbrali shf shfmt -s -w .
abbrali fi fmtinv
abbrali dnsq 'sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder'

function tex --argument-names texfile
    if test -z "$texfile"; or not test -f "$texfile"
        printf 'Usage: %s %s\n' "$(status function)" '<main.tex>' >&2
        return 1
    end
    set texfile "$(path resolve "$texfile")"
    set -l texbase "$(path basename "$texfile")"
    set -l dir "$(path dirname "$texfile")"
    cdc "$dir" latexmk -pdf -silent -pv "$texbase"
    fswatch -r0 -e '.*' -i '\.tex$' "$dir" | while read -l -z path
        set path "$(string replace "$dir/" '' "$path")"
        printf '%s+%s%s\n' "$(set_color --bold)" "$path" "$(set_color reset)"
        cdc "$dir" latexmk -pdf -silent "$texbase"
    end
end

function noise
    if test "$(path resolve -- "$PWD")" != "$(path resolve -- "$noise")"
        cdc "$noise" noise $argv
        return
    end
    git add -A; or return
    set -l commit_args
    if test "$(git diff --cached --name-only)" = fish/fish_history
        set commit_args -m 'fish_history: Update' -e
    end
    git commit $commit_args; or return
    git push
end

function fair --argument-names n
    if test "$(path resolve -- "$PWD")" != "$(path resolve -- "$fair_repo")"
        cdc "$fair_repo" fair $argv
        return
    end
    test -n "$n"; or set n 1
    set -l msg "$(git show -s --format=%s)"
    set -l msgn "$(string match -rg ': ([0-9]+)$' -- "$msg")"; or set msgn 0
    if not string match -qr '^[0-9]{1,4}$' -- "$n"; or test "$n" -lt 1
        printf '%s: 1 <= n <= 9999\n' "$(status function)" >&2
        return 1
    end
    for i in $(seq 1 "$n")
        set msgn "$(math "$msgn" + 1)"
        git commit --allow-empty --only -m "count: $msgn"; or return
    end
    git push
end

set -g dotfiles "$(path resolve -- "$(status filename)/../..")"
function add_cdpath
    set -l mode --append
    argparse p/prepend -- $argv; or return
    set -q _flag_prepend; and set mode --prepend
    for path in $argv
        if not contains -- "$path" $CDPATH
            set $mode --path -g CDPATH "$path"
        end
    end
end

source "$dotfiles/fish/git.fish"
source "$dotfiles/fish/github.fish"
source "$dotfiles/fish/prompt.fish"
source "$dotfiles/fish/cd.fish"

add_cdpath . "$dotfiles" ~

if test "$PWD" = "$HOME"
    cd "$dotfiles"
end
