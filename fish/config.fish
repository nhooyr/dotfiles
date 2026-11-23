if not set -q HOMEBREW_PREFIX
    /opt/homebrew/bin/brew shellenv fish | source
end
set -gx GOPATH ~/.local/share/gopath
fish_add_path --prepend --move --path ~/.local/bin/dotfiles \
    ~/.local/share/bin \
    ~/.local/bin \
    /opt/homebrew/share/git-core/contrib/diff-highlight \
    "$GOPATH/bin" \
    /opt/homebrew/share/google-cloud-sdk/bin \
    /opt/homebrew/opt/openjdk/bin \
    /opt/homebrew/bin
if not status is-interactive
    return 0
end

set -g dotfiles "$(path resolve -- "$(status filename)/../..")"
set -g nhooyr ~/code/nhooyr
set -g notes "$nhooyr/notes"

tabs -4
set -gx LESS -RXF -ix4 --use-color -DBK -DCK -DEms -DMcd -DNcd -DPks -DRKs -DSbws
set -g fish_greeting
set -gx MANPAGER nvim +Man!
set -gx EDITOR nvim
function abbrali --argument-names name
    abbr -a "$name" $argv[2..]
    alias "$name" "$argv[2..]"
end
abbr -a --position anywhere '&&' '; and'
abbr -a --position anywhere '||' '; or'
abbr -a '!' not
abbrali v nvim
abbrali vi nvim
abbrali vim nvim
abbrali vid vidir
function vidir
    if set -q argv[1]
        cdc "$argv[1]" vidir $argv[2..]
        return
    end
    nvim +Vidir $argv
end
abbrali e nvim
abbrali ec v '"$dotfiles/fish/config.fish"'
abbrali ev v '"$dotfiles/nvim/init.vim"'
abbrali cdd cdc '"$dotfiles"'
abbr -a --command sudo vi nvim
abbr -a --command sudo vim nvim
abbrali s sudo
alias sudo='sudo --preserve-env=SSH_TTY'
abbr -a --position anywhere '$pbp' '"$(pbpaste)"'
abbrali pbp pbpaste
abbrali pbn 'pbp | pbc'
abbrali pwdc 'pwd | hpath | pbc'
abbrali realpc realpathc
function realpathc --argument-names path --description "Print and copy an absolute pathname"
    realpath "$path" | hpath | pbc
end
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
set -g fish_color_autosuggestion 808080
set -g fish_color_comment brblack --italic
abbrali r reload
function reload
    source "$__fish_config_dir/config.fish"
    history merge
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
        LC_COLLATE=C command gls --group-directories-first $argv
    else
        LC_COLLATE=C command ls $argv
    end
end
alias l='ls --color -lhF'
alias ll='ls --color -lhAF'
abbr -a fd fd -HLE .git
abbr -a bfs bfs -L -exclude -name .git
abbrali rgf rg -F
abbrali rgi rg -i
abbrali rgp rg -P
alias rg="rg -Sn --search-zip --no-heading \
    --colors=path:fg:cyan \
    --colors=line:fg:magenta \
    --colors=match:none \
    --colors=match:fg:white \
    --colors=match:bg:blue \
"
function f
    find . -iname "*$argv*" | grf "$argv"
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
abbrali o. open .
abbrali of finder
abbrali fi finder
abbrali finder open -R
abbrali safari open -a Safari
abbrali chrome open -a 'Google Chrome'
abbrali t time
abbrali diff diff -r
abbrali esc string escape
abbrali m man
abbr -a --set-cursor ma math "'%'"
abbrali tra trash
function man
    command man $argv 2>/dev/null
end
abbrali to touch

abbrali sshak ssh-add --apple-load-keychain
set -q TMPDIR; or set -gx TMPDIR /tmp
if not test -f "$TMPDIR/__aqsnow_ssh_keychain_loaded"
    sshak -q; and touch "$TMPDIR/__aqsnow_ssh_keychain_loaded"
end
abbrali sshq ssh -O exit
abbrali sshu ssh -oControlPath=none
abbrali ssha ssh-add
abbrali sshfl sshf -L
abbrali sshfr sshf -R
abbrali sshfs sshf -D
abbrali py python3
function pyc --wraps 'python3 -c'
    python3 -c "print($argv)"
end
abbrali b brew
abbrali bi brew install
abbrali bu brew upgrade
abbrali bcl brew cleanup
abbrali tm tmux
abbrali tmuxl tmux list-sessions
abbrali tmuxa tmux attach-session
abbrali tmuxq tmux kill-server
abbrali tmuxk tmux kill-server
abbr -a --command tmux l list-sessions
abbr -a --command tmux a attach-session
abbr -a --command tmux k kill-server
abbr -a --command tmux q kill-server
abbrali cx codex
abbr -a --command codex a agents

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

bind -M default -m insert alt-enter accept-autosuggestion execute
bind -M insert alt-enter accept-autosuggestion execute

for mode in default insert
    bind -M "$mode" alt-e 'aqsnow_init_rendezvous; and edit_command_buffer' 'set -g fish_bind_mode insert' aqsnow_rendezvous
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
        case 'git commit --amend' '*; and git commit --amend' gcma '*; and gcma'
            gpf
        case 'git commit*' '* git commit' 'gcm*' '* gcm*' 'gacm*' '* gacm*'
            git push
    end
end
# Always disable bracketed paste queries. https://github.com/junegunn/fzf/issues/4963
alias fzf='TERM_PROGRAM=Apple_Terminal command fzf'
# Use the monochrome base with ANSI input colors enabled.
set -gx FZF_DEFAULT_OPTS "--style=minimal --layout=reverse --height=~50% --min-height=0 --cycle \
    --bind=ctrl-/:toggle-preview --bind=ctrl-s:toggle-sort --no-mouse --scroll-off=0 --info=inline-right \
    --color=bw --color --color=query:regular,info:italic,hl:underline,fg+:regular:reverse:strip,\
hl+:reverse:underline:strip,pointer:magenta:bold"
# Display no prefix by default in history view.
set -gx FZF_CTRL_R_OPTS "--with-nth 3.. --bind 'alt-t:change-with-nth(2..|1,3..|3..)'"
for mode in default insert
    bind -M "$mode" ctrl-r 'fzf_accept_and_run fzf-history-widget'
    bind -M "$mode" ctrl-t 'fzf_accept_and_run fzf-file-widget'
    bind -M "$mode" alt-v 'fzf_accept_and_run fzf-path-widget'
    bind -M "$mode" alt-c 'fzf_accept_and_run fzf-cd-widget'
    bind -M "$mode" shift-tab 'fzf_accept_and_run fzf_complete'
end
function aqsnow_fzf_diralis_add
    for name in $argv
        contains -- "$name" $aqsnow_fzf_diralis; or set -ga aqsnow_fzf_diralis "$name"
    end
end
aqsnow_fzf_diralis_add HOME nhooyr dotfiles notes noise

# Editors launched by commands need to inherit the handoff path.
function aqsnow_init_rendezvous --on-event fish_preexec
    set -q __aqsnow_rendezvous_dir; and return
    set -e AQSNOW_FISH_RENDEZVOUS
    set -l rendezvous_dir "$(mktemp -d)"; or return
    set -g __aqsnow_rendezvous_dir "$rendezvous_dir"
    set -gx AQSNOW_FISH_RENDEZVOUS "$rendezvous_dir/rendezvous"
    function aqsnow_rm_rendezvous --on-event fish_exit --inherit-variable rendezvous_dir
        rm -rf -- "$rendezvous_dir"
    end
end
function aqsnow_run_requested
    test -s "$AQSNOW_FISH_RENDEZVOUS"; or return 1
    if not printf '%s\n' '<M-v>' | cmp -s - "$AQSNOW_FISH_RENDEZVOUS"
        rm -- "$AQSNOW_FISH_RENDEZVOUS"
        return 0
    end
    rm -- "$AQSNOW_FISH_RENDEZVOUS"
    fzf_accept_and_run fzf-path-widget
    return 1
end
function aqsnow_rendezvous
    aqsnow_run_requested; or return 0
    commandline -f execute
    set -g fish_bind_mode insert
end

abbrali vsce NO_COLOR=1 command vsce
abbrali bun NO_COLOR=1 command bun
abbrali shf shfmt -s -w .
abbrali fmti fmtinv
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
    set -l last_path
    fswatch -r0 --batch-marker='' -e '.*' -i '\.tex$' "$dir" | while read -zl path
        if test -z "$path"
            set -e last_path
            cdc "$dir" latexmk -pdf -silent "$texbase"
        else
            set path "$(string replace "$dir/" '' "$path")"
            if test "$path" = "$last_path"
                continue
            end
            set last_path "$path"
            printf '%s+%s %s%s\n' "$(set_color --bold)" "$(date '+%X')" "$path" "$(set_color reset)"
        end
    end
end

abbrali wb watchbell
function watchbell --argument-names pattern
    if test -z "$pattern"
        set pattern '.*'
    end
    set -l last_path
    fswatch -r0 --batch-marker='' -e '.*' -i "$pattern" . | while read -zl path
        if test -z "$path"
            set -e last_path
            printf '\a'
        else
            set path "$(string replace "$PWD/" '' "$path")"
            if test "$path" = "$last_path"
                continue
            end
            set last_path "$path"
            if test "$(path basename "$path")" = 4913
                continue
            end
            printf '+%s %s\n' "$(date '+%X')" "$path"
        end
    end
end

function biglines --argument-names file \
    --description "Print lines in a file with their lengths, sorted by length"
    awk '{ print length, $0 }' "$file" | sort -rn | sed -E "s/^[0-9]+/$(set_color magenta)&$(set_color reset)/" | less
end

abbrali noise 'cdc "$noise" gacmp -em "fish_history: Update"'

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

abbrali notep 'cdc "$notes" gacmp -em Update'
function note --description '$EDITOR $notes/YYYY/MM/DD.md'
    set -l note "$notes/$(date '+%Y/%m/%d').md"
    if test -e "$note"
        $EDITOR "$note"
        return
    end
    printf '# %s\n* %s *\n\n\n' "$(date '+%B %d, %Y')" "$(date '+%A')" | note="$note" $EDITOR - \
        '+execute "file " . fnameescape($note)' \
        '+filetype detect' \
        '+normal! G' +startinsert
end

function rootimg --description 'Shrink image to 1/4' --argument-names img
    if test -z "$img"; or set -q argv[2]
        printf 'Usage: %s <img>\n' "$(status current-function)" >&2
        return 1
    end
    if contains -- "$img" -h --help
        printf 'Usage: %s <img>\n' "$(status current-function)"
        return 0
    end
    set -l img_dst "$(path basename --no-extension "$img")"
    set img_dst "$img_dst-root$(path extension "$img")"
    set img_dst "$(path dirname "$img")/$img_dst"
    magick "$img" -resize 50% "$img_dst"
end

abbrali netq networkquality

source "$dotfiles/fish/git.fish"
source "$dotfiles/fish/prompt.fish"
source "$dotfiles/fish/cd.fish"

if test "$PWD" = "$HOME"
    cd -- "$dotfiles"
end
