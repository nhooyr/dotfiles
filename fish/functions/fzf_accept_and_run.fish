source "$(status dirname)/../fzf_upstream.fish"; or return

function fzf_accept_and_run --argument-names widget
    aqsnow_init_rendezvous; or return
    # Indices preserve fzf's empty-selection guard without copying filenames.
    set -l action "alt-enter:execute-silent(test -n '{+n}'; and printf exec > $(string escape -- "$AQSNOW_FISH_RENDEZVOUS"))+accept"
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
    set -l token "$(commandline --current-token --tokens-expanded)"
    # Only scan the whole home directory when ./ explicitly requests it.
    if test "$dir" -ef ~; and not string match -q -- './*' "$token"
        set dir ''
    end
    set -l global_dir "$nhooyr"
    set -l tokens $(commandline --cut-at-cursor --current-process --tokens-expanded)
    while contains -- "$tokens[1]" and or not '!' command builtin exec time if while
        set -e tokens[1]
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
        set -a dirs --dirali "$direnv" $(path normalize -Z -- "$$name" | string split0)
    end

    set -l shell $(string join ' ' -- $(string escape -- $(status fish-path) -c))
    # Score without a leading $, falling back to the full path for queries containing $.
    set -lx FZF_DEFAULT_OPTS $(__fzf_defaults \
        '--reverse --scheme=path --delimiter=^[$] --nth=2,..' \
        "$opts --read0 --print0 --with-shell=$(string escape -- "$shell")")
    set -lx FZF_DEFAULT_OPTS_FILE
    printf '%s\0' "$parsed[2]" | read --null --local --array --tokenize query; or return
    # ./ selects local search; keep the execution prefix only for file/path queries.
    if string match -q -- './*' "$token"
        test "$widget" = fzf-cd-widget; or set query "$token"
        set global_dir ''
    else if not set -q tokens[1]; or contains -- "$tokens[1]" cd cdc
        set -a flags --cdpath "$CDPATH"
    end
    set -l result $(fzf-paths $flags "$dir" "$global_dir" "$type" $dirs | fzf --query="$query" | string split0)
    if set -q result[1]
        set -l cdpath_selected 0
        string match -q -- '$CDPATH/*' "$result[1]"; and set cdpath_selected 1
        set -l escaped
        for target in $result
            if string match -q -- '$CDPATH/*' "$target"
                set -l name $(string split --max 1 -- '$CDPATH/' "$target")[2]
                set -l selected "$(string escape -n -- "$name")"
                if test -d "$name"
                    for root in $CDPATH
                        # Skip the local directory and use the first different CDPATH match.
                        if test -d "$root/$name"; and not test "$name" -ef "$root/$name"
                            set -l path "$root/$name"
                            string match -q -- '/*' "$path"; or set path "$PWD/$path"
                            set path $(path normalize -Z -- "$path" | string split0)
                            set path $(aqsnow_fzf_path_alias "$path" | string split0)
                            set selected "$(aqsnow_fzf_path_quote "$path")"
                            break
                        end
                    end
                end
                set -a escaped "$selected"
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

function aqsnow_fzf_path_alias --argument-names target
    set -l aliased "$target"
    set -l longest 0
    for name in $aqsnow_fzf_diralis
        test -d "$$name"; or continue
        set -l directory $(path normalize -Z -- "$$name" | string split0)
        set -l length $(string length -- "$directory")
        test "$length" -gt "$longest"; or continue
        if string match -qr -- '^'$(string escape --style=regex -- "$directory")'(/|$)' "$target"
            set -l direnv '$'$name
            test "$name" = HOME; and set direnv '~'
            set -l suffix $(string split --max 1 -- "$directory" "$target")[2]
            set aliased "$direnv$suffix"
            set longest "$length"
        end
    end
    printf '%s\0' "$aliased"
end

function aqsnow_fzf_path_quote --argument-names target
    for name in $aqsnow_fzf_diralis
        set -l direnv '$'$name
        test "$name" = HOME; and set direnv '~'
        if test "$target" = "$direnv"; or string match -q -- "$direnv/*" "$target"
            # Keep the leading $ or ~ expandable; escape everything else.
            string sub --start 2 -- "$(string escape -n -- "$target")"
            return
        end
    end
    string escape -n -- "$target"
end
