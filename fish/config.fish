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
set -gx VISUAL nvim
set -gx EDITOR "$VISUAL"
function abbrali --argument-names name
    abbr -a "$name" $argv[2..]
    alias "$name" "$argv[2..]"
end
abbr -a --position anywhere '!!' '"$history[1]"'
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
abbrali f fd
alias bfs='bfs -L -exclude -name .git'
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
abbrali gr grep
abbrali gre grep
abbrali gree grep -E
abbrali gref grep -F
abbrali grei grep -i
abbrali grer grep -R
abbrali grev grep -v
abbrali grp grep
abbrali grpe grep -E
abbrali grpf grep -F
abbrali grpi grep -i
abbrali grpr grep -R
abbrali grpv grep -v
abbrali grepe grep -E
abbrali grepf grep -F
abbrali grepi grep -i
abbrali grepr grep -R
abbrali grepv grep -v
abbr -a --command grep e -- -E
abbr -a --command grep f -- -F
abbr -a --command grep i -- -i
abbr -a --command grep r -- -R
abbr -a --command grep v -- -v
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
abbrali typa type -as
abbrali typea type -as
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
abbrali beep printf '\a'

function cdpath_add
    argparse --exclusive p,a,b h/help p/prepend a/after= b/before= -- $argv; or return
    if set -q _flag_help
        printf '%s\n' 'Usage: cdpath_add [-p|--prepend | -a|--after ENTRY | -b|--before ENTRY] DIRECTORY...' \
            'Add directories to CDPATH, ignoring empty and duplicate entries.' \
            'By default append them; --after and --before require an existing CDPATH entry.'
        return 0
    end
    set -l index "$(count $CDPATH)"
    set -q _flag_prepend; and set index 0
    set -l anchor $_flag_before $_flag_after
    if set -q anchor[1]
        set index "$(contains -i -- "$anchor" $CDPATH)"
        if test -z "$index"
            printf '%s: %s is not in CDPATH\n' "$(status function)" "$(string escape -- "$anchor")" >&2
            return 1
        end
        set -q _flag_before; and set index "$(math "$index - 1")"
    end

    set -l paths
    for path in $argv
        if test -n "$path"; and not contains -- "$path" $CDPATH $paths
            set -a paths "$path"
        end
    end
    set -q paths[1]; or return 0
    set -l head
    test "$index" -gt 0; and set head $CDPATH[..$index]
    set -l next_index "$(math "$index + 1")"
    set --path -g CDPATH $head $paths $CDPATH[$next_index..]
end
cdpath_add . "$dotfiles" "$notes" "$nhooyr" ~/code ~

abbr --add dotdot --regex '^\.\.\.+$' --function multicd
abbrali pd prevd
abbrali bd prevd
abbrali nd nextd
abbrali md mkdir -p
abbrali mcdt 'cd -- "$(mktemp -d)"'

type -q _cd; or functions -c cd _cd
function cd --description 'Change directory' --argument-names path
    switch "$path"
        case \-
            _cd $argv
            return
        case --
            set path $argv[2..]
            if test "$(count $path)" -ne 1
                _cd $argv
                return
            end
    end
    if ! test -d "$path"; and test -e "$path"
        cdf "$path"
        return
    end
    _cd $argv
end

abbrali g git
abbrali grv 'git rev-parse --abbrev-ref HEAD | pbc'
abbrali grvs 'git rev-parse --short HEAD | pbc'
abbrali gsh git show --stat --patch
abbrali gshs git show --stat
abbrali gsha git show --stat --patch --format=fuller
abbrali gsht 'git show -s --format=%s | pbc'
abbrali gshb 'git show -s --format=%b | pbc'
abbrali ga git add -A
abbrali gap git add -p
abbrali gai git add -i
abbrali gp git push
abbrali gps git push
abbrali gpf git push --force-with-lease
function git_commit --wraps 'git commit'
    git -c status.relativePaths=false commit $argv
end
abbrali gcm git_commit
abbr -a gacm 'ga; and gcm'
function gacm
    ga; and gcm $argv
end
abbr -a gacmp 'ga; and gcm; and gp'
function gacmp
    ga; and gcm $argv; and gp
end
abbrali gcma git_commit --amend
abbr -a gacma 'ga; and gcma'
abbr -a fcm 'ga; and gcma'
function gacma
    ga; and gcma $argv
end
abbrali gcmf git_commit --fixup
abbrali grb git_rebase
abbrali grbi git_rebase -i
abbrali grbr git_rebase -i --root
abbrali grbc git_rebase --continue
abbrali grbs git_rebase --skip
abbrali grba git_rebase --abort
abbrali gs git status
abbrali gd git diff --patch-with-stat
abbrali gdc git diff --patch-with-stat --cached
abbr -a --command git diffc diff --patch-with-stat --cached
abbrali gdi git diff --patch-with-stat --no-index
abbrali grt git reset
abbrali grtp git reset -p
abbrali grth git reset --hard
abbrali grm git rm
abbrali grmr git rm -r
abbrali grmf git rm -f
abbrali grmrf git rm -rf
abbrali grmc git rm --cached
abbrali grmcr git rm --cached -r
abbrali grmcrf git rm --cached -rf
abbrali gl git_log
abbrali gla git_log --format=fuller
abbrali glp git_log -p
abbrali glo git_log --oneline
abbrali glot git_log --format=%s
abbrali glol git_log --oneline \| wc -l
abbrali glss git_log --show-signature
abbrali gls git ls-files
abbrali gcl git clone
function gcld
    git clone $argv; and cd "$(path basename -- $argv[-1])"
end
abbrali gpl git pull
abbrali gf git fetch
abbrali gfa git fetch --all
abbrali gfp git fetch --prune-tags
abbrali gro git remote -v
abbrali groa git remote add
abbrali gros git remote set-url
abbrali grou git remote get-url
abbrali gror git remote rename
abbrali grod git remote remove
abbrali gb git branch -vv
abbrali gbm git branch -vv -m
abbrali gbu git branch -vv -u
abbrali gba git branch -vv -a
abbrali gbr git branch -vv -r
abbrali gbd git branch -vv -d
abbrali gbD git branch -vv -D
abbrali gst git stash push -u
abbrali gstk git stash push -u --keep-index
abbrali gsta git stash apply
abbrali gsts git stash show
abbrali gstsp git stash show -p
abbrali gstp git stash pop
abbrali gstl git stash list
abbrali gstd git diff stash@{0}
abbrali gstdd git stash drop
abbrali gbl git blame
abbrali gch git checkout
abbrali gchb git checkout -b
abbrali gt git tag
abbrali grs git restore
abbrali grsp git restore -p
abbrali grss git restore -S
abbrali grsw git restore -W
abbrali grssw git restore -SW
abbrali gcln git clean -ndX
abbrali gclx git clean -fdX

abbrali .c 'gcd && ./commit'
abbrali .co 'gcd && ./commit'
abbrali .fmt 'gcd && ./ci/fmt.sh'
abbrali .lint 'gcd && ./ci/lint.sh'
abbrali .test 'gcd && ./ci/test.sh'
abbrali .run 'gcd && ./ci/run.sh'
abbrali app git apply

alias gh='NO_COLOR=1 command gh'
abbrali ghgp ghg -p
abbrali ghf 'gh repo fork --remote; and gh repo set-default upstream'
abbrali ghch gh pr checkout
abbrali ghep gh pr create --web --fill-verbose
abbrali ghl gh repo list --visibility public --source --no-archived --json url --jq '.[].url'

abbrali tabt column -ts '\t'
abbrali dt dirt
abbrali dtb dirtb
abbrali dtc dirtci
abbrali dtci dirtci

abbrali imps "ga; and gcm -em 'imps'"

abbrali glfs git lfs
abbrali gfr git filter-repo --invert-paths --path

abbrali gsub git submodule
abbrali gsubu git submodule update --init --recursive
abbrali grl git reflog
abbrali grfl git reflog
abbrali gcp git cherry-pick
abbrali gcpc git cherry-pick --continue
abbrali gcps git cherry-pick --skip
abbrali gcpa git cherry-pick --abort
abbrali gmb git merge-base HEAD origin
abbrali gclean git clean -fdXn
abbrali gcleanu git clean -fdn
abbrali gcleana git clean -fdxn

bind -M default -m insert alt-enter accept-autosuggestion execute
bind -M insert alt-enter accept-autosuggestion execute
bind -M insert alt-r 'commandline -i \n $(commandline --search-field >/dev/null; and printf --search-field)' expand-abbr
bind -M default backspace 'fish_vi_start_operator delete'

for mode in default insert
    bind -M "$mode" alt-e 'rendezvous_init; and fish_cursor_end_mode=exclusive edit_command_buffer; and rendezvous'
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
    test "$code" -ne 0; and return
    if test "$(test -s "$RENDEZVOUS_FISH"; and cat "$RENDEZVOUS_FISH")" != exec
        return
    end

    set cmdline "$(string replace -r '[;[:space:]]+$' '' -- "$cmdline")"
    set -l command $(commandline --input="$cmdline" --current-process --tokens-expanded)
    contains -- "$command[1]" and or; and set -e command[1]
    set -l push
    if test "$command[1]" = cdc
        set -a push $command[1..2]
        set -e command[1..2]
    end
    test "$command[1]" = command; and set -e command[1]
    if test "$command[1]" = git; and test "$command[2]" = commit
        set command gcm $command[3..]
    end
    contains -- "$command[1]" git_commit gcm gacm gcmf gcma gacma ./commit; or return 0
    if contains -- "$command[1]" gcma gacma; or contains -- --amend $command[2..]
        set -a push gpf
    else
        set -a push git push
    end
    $push
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

function rendezvous_init --on-event fish_preexec
    if set -q RENDEZVOUS_FISH
        echo -n >"$RENDEZVOUS_FISH"
        return
    end
    set -e RENDEZVOUS_FISH
    set -l rendezvous_dir "$(mktemp -d)"; or return
    set -g __rendezvous_dir "$rendezvous_dir"
    set -gx RENDEZVOUS_FISH "$rendezvous_dir/rendezvous"
    function aqsnow_rm_rendezvous --on-event fish_exit --inherit-variable rendezvous_dir
        rm -rf -- "$rendezvous_dir"
    end
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

abbrali notep 'cdc "$notes" gacm'
abbrali netq networkquality

source "$dotfiles/fish/prompt.fish"

if test "$PWD" = "$HOME"
    cd -- "$dotfiles"
end
