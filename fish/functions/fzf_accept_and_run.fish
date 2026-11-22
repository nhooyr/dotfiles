source "$(status dirname)/../fzf_upstream.fish"; or return

function fzf_accept_and_run --argument-names widget
    aqsnow_init_rendezvous; or return
    set -l action "alt-enter:execute-silent(printf %s {+} > $(string escape -- "$AQSNOW_FISH_RENDEZVOUS"))+accept"
    set -l option "--bind=$(string escape -- "$action")"

    for name in FZF_CTRL_R_OPTS FZF_CTRL_T_OPTS FZF_ALT_C_OPTS FZF_COMPLETION_OPTS FZF_EXPANSION_OPTS
        set --function --export "$name" "$$name $option"
    end

    if contains -- "$widget" fzf-file-widget fzf-cd-widget fzf-path-widget
        fzf_path_widget "$widget"
    else
        $widget
    end
    aqsnow_rendezvous
end

function fzf_path_widget --argument-names widget
    set -l parsed $(__fzf_parse_commandline)
    set -l dir "$(string unescape -- "$parsed[1]")"
    # Skip whole-home scans; the HOME alias below still abbreviates paths.
    if test "$dir" -ef ~
        set dir ''
    end
    set -l tokens $(commandline --cut-at-cursor --current-process --tokens-expanded)
    while contains -- "$tokens[1]" and or not '!' command builtin exec time if while
        set -e tokens[1]
    end
    set -l --unexport CDPATH $CDPATH
    if not set -q tokens[1]; or contains -- "$tokens[1]" cd cdc
        set -x CDPATH $CDPATH
    end
    set -l type -fd
    set -l flags
    set -l opts "--multi $FZF_CTRL_T_OPTS"
    if test "$widget" = fzf-file-widget
        set type -f
    else if test "$widget" = fzf-cd-widget
        set type -d
        set opts "$FZF_ALT_C_OPTS --no-multi"
    end
    if not set -q tokens[1]
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
    # Score without a leading $, falling back to the full path for queries containing $.
    set -lx FZF_DEFAULT_OPTS $(__fzf_defaults \
        '--reverse --scheme=path --delimiter=^[$] --nth=2,..' \
        "$opts --read0 --print0 --with-shell=$(string escape -- "$shell")")
    set -lx FZF_DEFAULT_OPTS_FILE
    printf '%s\0' "$parsed[2]" | read --null --local --array --tokenize query; or return
    # Upstream path parsing normalizes away an explicit execution prefix.
    set -l token "$(commandline --current-token --tokens-expanded)"
    if string match -q -- './*' "$token"
        set query "$token"
    end
    set -l result $(fzf-paths $flags "$dir" "$nhooyr" "$type" $dirs | fzf --query="$query" | string split0)
    if set -q result[1]
        set -l cdpath_selected 0
        string match -q -- '$CDPATH/*' "$result[1]"; and set cdpath_selected 1
        set -l escaped
        for target in $result
            if string match -q -- '$CDPATH/*' "$target"
                set -l name $(string split --max 1 -- '$CDPATH/' "$target")[2]
                set -a escaped "$(string escape -n -- "$name")"
            else
                set -a escaped "$(aqsnow_fzf_path_quote "$target")"
            end
        end
        if not set -q tokens[1]
            set -l target "$result[1]"
            # Resolve directory aliases without evaluating the selected path.
            for name in $aqsnow_fzf_diralis
                set -l direnv '$'$name
                test "$name" = HOME; and set direnv '~'
                if test "$target" = "$direnv"; or string match -q -- "$direnv/*" "$target"
                    set -l suffix $(string split --max 1 -- "$direnv" "$target")[2]
                    set target "$$name$suffix"
                    break
                end
            end
            set -l directory "$cdpath_selected"
            test -d "$target"; and set directory 1
            if test "$(count $result)" -eq 1; and test "$directory" -eq 1
                set -p escaped cd --
            else if not string match -q -- './*' "$result[1]"
                set -p escaped nvim --
            end
        else if test "$widget" != fzf-cd-widget; and test "$(path basename -- "$tokens[1]")" = nvim; and not contains -- -- $tokens; and test -z "$parsed[3]"
            set -p escaped --
        end
        commandline -rt -- "$(string join -- ' ' $parsed[3]$escaped) "
    end
    commandline -f repaint
end

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
