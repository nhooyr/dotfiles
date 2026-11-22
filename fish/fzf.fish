fzf --fish | source
set -gx FZF_DEFAULT_OPTS "--style=minimal --layout=reverse --height=~50% --min-height=0 --cycle \
    --bind=ctrl-/:toggle-preview --bind=ctrl-s:toggle-sort --no-mouse --scroll-off=0 --info=inline-right \
    --color=bw,query:regular,info:italic,hl:underline,fg+:regular:reverse,\
hl+:reverse:underline,pointer:magenta:bold"
# Display no prefix by default in history view.
set -gx FZF_CTRL_R_OPTS "--with-nth 3.. --bind 'alt-t:change-with-nth(2..|1,3..|3..)'"
function aqsnow_fzf_diralis_add
    for name in $argv
        contains -- "$name" $aqsnow_fzf_diralis; or set -ga aqsnow_fzf_diralis "$name"
    end
end
aqsnow_fzf_diralis_add HOME nhooyr dotfiles notes noise

function aqsnow_fzf_path_quote --argument-names target
    for name in $aqsnow_fzf_diralis
        set -l direnv '$'$name
        test "$name" = HOME; and set direnv '~'
        if test "$target" = "$direnv"; or string match -q -- "$direnv/*" "$target"
            if test "$direnv" = '~'
                string replace -- '\~' '~' "$(string escape -n -- "$target")"
            else
                set -l suffix $(string split --max 1 -- "$direnv" "$target")[2]
                printf '"%s' "$direnv"
                # Escape only characters that are special inside double quotes.
                for char in $(string split '' -- "$suffix")
                    contains -- "$char" '\\' '"' '$'; and printf '\\'
                    printf '%s' "$char"
                end
                printf '"\n'
            end
            return
        end
    end
    string escape -n -- "$target"
end

function fzf_path_widget --argument-names widget
    set -l parsed $(__fzf_parse_commandline)
    set -l dir "$(string unescape -- "$parsed[1]")"
    # Skip whole-home scans; the HOME alias below still abbreviates paths.
    if test "$dir" -ef ~
        set dir ''
    end
    set -l tokens $(commandline --cut-at-cursor --current-process --tokens-expanded)
    while set -q tokens[1]; and contains -- "$tokens[1]" and or not '!' command builtin exec time if while
        set -e tokens[1]
    end
    set -l type -fd
    set -l flags
    set -l opts "--multi $FZF_CTRL_T_OPTS"
    if test "$widget" = fzf-cd-widget
        set type -d
        set opts "$FZF_ALT_C_OPTS --no-multi"
    else if not set -q tokens[1]
        set flags --keep-dot
    end

    set -l dirs
    for name in $aqsnow_fzf_diralis
        test -d "$$name"; or continue
        set -l direnv '$'$name
        test "$name" = HOME; and set direnv '~'
        set -a dirs "$direnv" $(path normalize -Z -- "$$name" | string split0)
    end

    set -l shell $(string join ' ' -- $(string escape -- $(status fish-path) -c))
    set -lx FZF_DEFAULT_OPTS $(__fzf_defaults '--reverse --scheme=path' "$opts --read0 --print0 --with-shell=$(string escape -- "$shell")")
    set -lx FZF_DEFAULT_OPTS_FILE
    printf '%s\0' "$parsed[2]" | read --null --local --array --tokenize query; or return
    set -l result $(fzf-paths $flags "$dir" "$nhooyr" "$type" $dirs | fzf --query="$query" | string split0)
    if set -q result[1]
        set -l escaped
        for target in $result
            set -a escaped "$(aqsnow_fzf_path_quote "$target")"
        end
        if test "$widget" = fzf-cd-widget
            commandline -r -- "cd -- $escaped[1]"
        else
            if set -q tokens[1]; and test "$(path basename -- "$tokens[1]")" = nvim; and not contains -- -- $tokens; and test -z "$parsed[3]"
                set -p escaped --
            end
            commandline -rt -- "$(string join -- ' ' $parsed[3]$escaped) "
        end
    end
    commandline -f repaint
end
function fzf_accept_and_run --argument-names widget
    set -l action "alt-enter:execute-silent(printf %s {+} > $(string escape -- "$AQSNOW_FISH_RENDEZVOUS"))+accept"
    set -l option "--bind=$(string escape -- "$action")"

    for name in FZF_CTRL_R_OPTS FZF_CTRL_T_OPTS FZF_ALT_C_OPTS FZF_COMPLETION_OPTS FZF_EXPANSION_OPTS
        set --function --export "$name" "$$name $option"
    end

    switch "$widget"
        case fzf-file-widget fzf-cd-widget
            fzf_path_widget "$widget"
        case '*'
            $widget
    end
    aqsnow_rendezvous
end
for mode in default insert
    bind -M "$mode" ctrl-r 'fzf_accept_and_run fzf-history-widget'
    bind -M "$mode" ctrl-t 'fzf_accept_and_run fzf-file-widget'
    bind -M "$mode" alt-v 'fzf_accept_and_run fzf-file-widget'
    bind -M "$mode" alt-c 'fzf_accept_and_run fzf-cd-widget'
    bind -M "$mode" shift-tab 'fzf_accept_and_run fzf_complete'
end

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
    if not printf '%s\n' '<M-v>' | cmp -s - "$AQSNOW_FISH_RENDEZVOUS"
        rm -- "$AQSNOW_FISH_RENDEZVOUS"
        return 0
    end
    rm -- "$AQSNOW_FISH_RENDEZVOUS"
    fzf_accept_and_run fzf-file-widget
    return 1
end
function aqsnow_rendezvous
    aqsnow_run_requested; or return 0
    aqsnow_exec
    set -g fish_bind_mode insert
end
