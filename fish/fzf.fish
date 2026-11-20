fzf --fish | source
set -gx FZF_DEFAULT_OPTS "--style=minimal --layout=reverse --height=~50% --min-height=0 --cycle \
    --bind=ctrl-/:toggle-preview --bind=ctrl-s:toggle-sort --no-mouse --scroll-off=0 --info=inline-right \
    --color=bw,query:regular,info:italic,hl:underline,fg+:regular:reverse,\
hl+:reverse:underline,pointer:magenta:bold"
set -gx FZF_ALT_C_OPTS --bind=alt-enter:accept
# Display no prefix by default in history view.
set -gx FZF_CTRL_R_OPTS "--with-nth 3.. --bind 'alt-t:change-with-nth(2..|1,3..|3..)'"
function aqsnow_fzf_diralis_add
    for name in $argv
        contains -- "$name" $aqsnow_fzf_diralis; or set -ga aqsnow_fzf_diralis "$name"
    end
end
aqsnow_fzf_diralis_add HOME nhooyr dotfiles notes noise

function aqsnow_fzf_path_expand --argument-names target
    for name in $aqsnow_fzf_diralis
        set -l label '$'$name
        test "$name" = HOME; and set label '~'
        if test "$target" = "$label"; or string match -q -- "$label/*" "$target"
            set -l parts (string split -m 1 -- "$label" "$target")
            set target "$$name$parts[2]"
            break
        end
    end
    printf '%s\0' "$target"
end

function fzf_path_widget --argument-names widget
    set -l parsed (__fzf_parse_commandline)
    set -l dir "$(string unescape -- "$parsed[1]")"
    set -l type -fd
    set -l keep_dot false
    set -l opts "--multi $FZF_CTRL_T_OPTS"
    if test "$widget" = fzf-cd-widget
        set type -d
        set opts "$FZF_ALT_C_OPTS --no-multi"
    else if test -z "$(commandline --cut-at-cursor --current-process --tokens-expanded)"
        and string match -q './*' -- "$(commandline --current-token --tokens-expanded)"
        if test "$dir" != .; and not string match -q './*' -- "$dir"
            set dir "./$dir"
        end
        set type -fdx
        set keep_dot true
    end

    set -l dirs
    for name in $aqsnow_fzf_diralis
        set -q "$name"; and test -d "$$name"; or continue
        set -l label '$'$name
        test "$name" = HOME; and set label '~'
        set -a dirs "$label" (path normalize -Z -- "$$name" | string split0)
    end

    set -l command $(string escape -- ~/.local/share/bin/fzf-paths "$dir" "$nhooyr" "$type" "$keep_dot" $dirs)
    set -l shell (string join ' ' -- (string escape -- (status fish-path) -c))
    set -lx FZF_DEFAULT_OPTS (__fzf_defaults '--reverse --scheme=path' "$opts --read0 --print0 --with-shell=$(string escape -- "$shell")")
    set -lx FZF_DEFAULT_OPTS_FILE
    set -l result (eval (string join ' ' -- $command) \| (__fzfcmd) --query=$parsed[2] | string split0)
    if set -q result[1]
        if test "$widget" = fzf-cd-widget
            cd -- (aqsnow_fzf_path_expand "$result[1]" | string split0)
            commandline -rt -- "$parsed[3]"
        else
            # Leave generated ~/ and $variable prefixes expandable; escape the filename.
            set -l escaped (string escape -n -- $result | string replace -r '^\\\\(?=[$~])' '')
            if test -n "$parsed[3]"
                set escaped (string replace -r '^~' '\$HOME' -- $escaped)
            end
            commandline -rt -- (string join -- ' ' $parsed[3]$escaped)' '
        end
    end
    commandline -f repaint
end
function fzf_accept_and_run --argument-names widget
    set -l action "alt-enter:execute-silent(printf %s {+} > $(string escape -- "$AQSNOW_FISH_RENDEZVOUS"))+accept"
    set -l option "--bind=$(string escape -- "$action")"

    set -lx FZF_CTRL_R_OPTS "$FZF_CTRL_R_OPTS $option"
    set -lx FZF_CTRL_T_OPTS "$FZF_CTRL_T_OPTS $option"
    set -lx FZF_COMPLETION_OPTS "$FZF_COMPLETION_OPTS $option"
    set -lx FZF_EXPANSION_OPTS "$FZF_EXPANSION_OPTS $option"

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
