# From `brew shellenv fish`, inlined to avoid starting Homebrew in fresh shells.
if not set -q HOMEBREW_PREFIX
    set -gx HOMEBREW_PREFIX /opt/homebrew
    set -gx HOMEBREW_CELLAR "$HOMEBREW_PREFIX/Cellar"
    set -gx HOMEBREW_REPOSITORY "$HOMEBREW_PREFIX"
    if test -n "$MANPATH"
        set -gx MANPATH "$(string replace -r '^:*(.*?):*$' ':$1' -- "$MANPATH")"
    end
    set -q INFOPATH; or set -g INFOPATH ''
    set -gx INFOPATH "$HOMEBREW_PREFIX/share/info" $INFOPATH
end
set -gx GOPATH ~/.local/share/gopath
fish_add_path --prepend --move --path ~/.local/bin/dotfiles \
    ~/.local/share/bin \
    ~/.local/bin \
    /opt/homebrew/share/git-core/contrib/diff-highlight \
    "$GOPATH/bin" \
    /opt/homebrew/share/google-cloud-sdk/bin \
    /opt/homebrew/opt/openjdk/bin \
    /opt/homebrew/bin \
    /opt/homebrew/sbin
if not status is-interactive
    return 0
end

set -gx dotfiles "$(path resolve -- "$(status filename)/../..")"
set -g nhooyr ~/code/nhooyr
set -g notes "$nhooyr/notes"

set -gx LESS -RXF -ix4 --use-color -DBK -DCK -DEks -DMcd -Dd- -DNK -DPks -DRKs -DSkY
set -gx PAGER pager
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
abbrali v. v .
abbrali vs nvim -o
abbrali vv nvim -O
abbrali vi nvim
abbrali vim nvim
abbrali nvi nvim
abbrali vid vidir
abbrali vid. vidir .
abbrali e nvim
abbrali ec v '"$dotfiles/fish/config.fish"'
abbrali ev v '"$dotfiles/nvim/init.vim"'
abbrali et v '"$dotfiles/nvim/lua/snippets.lua"'
abbrali cdd cdc '"$dotfiles"'
abbr -a --command sudo vi nvim
abbr -a --command sudo vim nvim
abbrali s sudo
alias sudo='sudo --preserve-env=SSH_TTY'
abbr -a --position anywhere '$pbp' '"$(pbpaste)"'
abbrali pbp pbpaste
abbrali pbn 'pbp | pbc'
abbr -a dali 'dirali "$PWD"'
abbr -a pwd 'pwd | hpath'
abbrali pwdc 'pwd | hpath | pbc'
abbrali rpc realpathc
abbrali rpc. realpathc .
abbrali realpc realpathc
abbrali realpc. realpathc .
fish_hybrid_key_bindings
set -g fish_color_error red --underline
set -g fish_color_quote green
set -g fish_color_search_match black --background=bryellow
set -g fish_color_selection black --background=bryellow
set -g fish_pager_color_progress --italic
set -g fish_pager_color_description cyan --italic
set -g fish_pager_color_prefix --underline
set -g fish_pager_color_selected_completion black
set -g fish_pager_color_selected_background --background=bryellow
set -g fish_pager_color_selected_description black --italic
set -g fish_color_autosuggestion 808080
set -g fish_color_comment brblack --italic
abbrali r reload

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
        LC_COLLATE=C command gls -v --group-directories-first $argv
    else
        LC_COLLATE=C command ls $argv
    end
end
alias l='ls --color -lhF'
alias ll='ls --color -lhAF'
alias fd='fd --hidden --follow --exclude .git --no-require-git'
abbr -a bfs bfs -L -exclude -name .git
set -gx BAT_PAGER 'N=0 pager'
abbrali rgf rg -F
abbrali rgi rg -i
abbrali rgp rg -P
abbr -a --set-cursor rgg "rg -g '*%'"
alias rg="rg -LSn --search-zip --no-heading --hidden -g '!.git' --no-require-git \
    --colors=path:fg:cyan \
    --colors=line:fg:magenta \
    --colors=match:none \
    --colors=match:fg:black \
    --colors=match:bg:11 \
"
alias fdg='fd --glob'
alias bigdirs='du -hd 1 | sort -hr | head -n 16'
abbr -a --set-cursor fdg "fdg '*%*'"
set -gx GREP_COLORS 'mt=30;103:fn=36:ln=35:bn=35:se=00'
set -gx GREP_COLOR '30;103'
abbr -a gr grep
abbr -a gre grep
abbrali grepe grep -E
abbrali grepf grep -F
abbrali grepi grep -i
abbrali grepr grep -R
abbr -a --command grep e -- -E
abbr -a --command grep f -- -F
abbr -a --command grep i -- -i
abbr -a --command grep r -- -R
abbrali ggf gg -F
abbr -a --set-cursor grepw "grepe '^\s+%'"
abbr -a --set-cursor ggw "gg '^[[:space:]]+%'"
abbrali ws gg "'[[:space:]]+\$'"

abbrali o open
abbrali o. open .
abbrali of finder
abbrali fi finder
abbrali finder open -R
abbrali safari open -a Safari
abbrali chrome open -a '"Google Chrome"'
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
abbrali pl perl
abbr -a --set-cursor plc perl -E "'say %'"
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

abbrali nlo nlogin
abbrali npw npass
abbrali nem nemail

abbrali chx chmod +x
abbrali ymp3 yt-dlp --audio-format mp3 -x --embed-thumbnail
abbrali num random 1 999

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
        if test "$CMD_DURATION" -gt 2000; and set -l focused_tty "$(osascript -e 'tell application "Terminal"
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
        case 'git commit*' '* git commit*' 'gcm*' '* gcm*' 'gacm*' '* gacm*'
            git push
        case './commit*' '* ./commit*'
            git push
    end
end
# Always disable bracketed paste queries. https://github.com/junegunn/fzf/issues/4963
alias fzf='TERM_PROGRAM=Apple_Terminal command fzf'
# Use the monochrome base with ANSI input colors enabled.
set -gx FZF_DEFAULT_OPTS "--style=minimal --layout=reverse --height=~50% --min-height=0 --cycle \
    --bind=ctrl-/:toggle-preview --bind=ctrl-s:toggle-sort --no-mouse --scroll-off=0 --info=inline-right \
    --color=bw --color \
    --color=query:regular,info:italic,pointer:black,\
fg+:black:regular:strip,bg+:bright-yellow,hl+:black:regular:underline:strip"
# Display no prefix by default in history view.
set -gx FZF_CTRL_R_OPTS '--with-nth 3.. --bind "alt-t:change-with-nth(2..|1,3..|3..),ctrl-x:trigger(shift-delete)"'
for mode in default insert
    bind -M "$mode" tab compgen complete
    bind -M "$mode" ctrl-r '_fzf fzf-history-widget'
    bind -M "$mode" ctrl-space '_fzf fzf-history-first-widget'
    bind -M "$mode" alt-o '_fzf fzf-recent-widget'
    bind -M "$mode" ctrl-t '_fzf fzf-file-widget'
    bind -M "$mode" alt-v '_fzf fzf-path-widget'
    bind -M "$mode" alt-space '_fzf fzf-path-first-widget'
    bind -M "$mode" alt-c '_fzf fzf-cd-widget'
    bind -M "$mode" shift-tab compgen '_fzf fzf_complete'
end
function aqsnow_fzf_diralis_add
    if not set -q aqsnow_fzf_diralis
        set -g aqsnow_fzf_diralis
        set -gx AQSNOW_DIRALIS ''
    end
    for name in $argv
        if test -n "$$name"; and not string match -q '/*' -- "$$name"
            printf 'aqsnow_fzf_diralis_add: alias %s requires an absolute path: %s\n' "$name" "$$name" >&2
            return 1
        end
        set -e "__aqsnow_fzf_dirali_$name"
        if not set -qx "$name"
            set -gx "$name" "$$name"
        end
        contains -- "$name" $aqsnow_fzf_diralis; and continue
        set -ga aqsnow_fzf_diralis "$name"
        if test -n "$AQSNOW_DIRALIS"
            set -gx AQSNOW_DIRALIS "$AQSNOW_DIRALIS:$name"
        else
            set -gx AQSNOW_DIRALIS "$name"
        end
    end
    return 0
end
aqsnow_fzf_diralis_add HOME TMPDIR nhooyr dotfiles notes noise fair

# Initialize the handoff path inherited by child processes.
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
    set -l request "$(cat "$AQSNOW_FISH_RENDEZVOUS")"
    rm -- "$AQSNOW_FISH_RENDEZVOUS"
    switch "$request"
        case exec
            return 0
        case path-widget recent-widget
            _fzf "fzf-$request"
    end
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

abbrali goi 'go install'
abbr -a --command go i install

abbrali wb watchbell

abbrali noisep 'cdc "$noise" gacmp'

abbrali notep 'cdc "$notes" gacmp'
abbrali netq networkquality

source "$dotfiles/fish/git.fish"
source "$dotfiles/fish/prompt.fish"
source "$dotfiles/fish/cd.fish"

if test "$PWD" = "$HOME"
    cd -- "$dotfiles"
end
