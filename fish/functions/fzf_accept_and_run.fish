source "$(status dirname)/../fzf_upstream.fish"; or return

function fzf_accept_and_run --argument-names widget
    aqsnow_init_rendezvous; or return
    # Indices preserve fzf's empty-selection guard without copying filenames.
    set -l action "alt-enter:execute-silent(test -n '{+n}'; and printf exec > $(string escape -- "$AQSNOW_FISH_RENDEZVOUS"))+accept"
    set -l option "--bind=$(string escape -- "$action")"

    for name in FZF_CTRL_R_OPTS FZF_CTRL_T_OPTS FZF_ALT_C_OPTS FZF_COMPLETION_OPTS FZF_EXPANSION_OPTS
        set --function --export "$name" "$$name $option"
    end

    if contains -- "$widget" fzf-file-widget fzf-cd-widget fzf-path-widget fzf-recent-widget
        fzf_path_widget "$widget"
    else
        $widget
    end
    aqsnow_rendezvous
end

function fzf_path_widget --argument-names widget
    set -l parsed $(__fzf_parse_commandline | string split0)
    set -l dir "$parsed[1]"
    set -l token "$(commandline --current-token --tokens-expanded)"
    # Only scan the whole home directory when ./ explicitly requests it.
    if test "$dir" -ef ~; and not string match -q -- './*' "$token"
        set dir ''
    end
    set -l global_dir "$nhooyr"
    set -l tokens $(commandline --cut-at-cursor --current-process --tokens-expanded)
    while contains -- "$tokens[1]" and or not '!' command builtin exec time if while else --; or string match -qr '^[[:alnum:]_]+=' -- "$tokens[1]"
        set -e tokens[1]
    end
    set -l type -fd
    set -l flags
    set -l opts "--multi $FZF_CTRL_T_OPTS"
    if contains -- "$widget" fzf-file-widget fzf-recent-widget
        set type -f
        if test "$widget" = fzf-recent-widget
            set opts "$opts --no-sort"
        end
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
        set -a dirs --dirali "$direnv" "$$name"
    end

    set -l shell $(string join ' ' -- $(string escape -- $(status fish-path) -c))
    # Ignore the leading $ and suffix; \x1f is the invisible marker for ordinary files.
    set -lx FZF_DEFAULT_OPTS $(__fzf_defaults \
        '--reverse --scheme=path --delimiter="^[$]|[/*=>@|\\\\x1f]$" --nth=2,.. --accept-nth=..' \
        "$opts --ansi --read0 --print0 --with-shell=$(string escape -- "$shell")")
    set -lx FZF_DEFAULT_OPTS_FILE
    set -l query "$parsed[2]"
    # ./ selects local search; only Alt-V keeps it in the query.
    if test "$widget" != fzf-recent-widget; and string match -q -- './*' "$token"
        test "$widget" = fzf-path-widget; and set query "$token"
        set global_dir ''
    else if not contains -- "$widget" fzf-file-widget fzf-recent-widget
        set -a flags --cdpath "$CDPATH"
    end
    set -l result
    if test "$widget" = fzf-recent-widget
        set result $(command nvim --headless -u NONE -n \
            -c 'lua io.write(table.concat(vim.v.oldfiles, "\0")); vim.o.shadafile = "NONE"' -c 'qa!' \
            | fzfpaths --read0 --color --classify $flags $dirs -- . '' -f \
            | fzf --query="$query" | string split0)
    else
        set result $(fzfpaths --color --classify $flags $dirs -- "$dir" "$global_dir" "$type" | fzf --query="$query" | string split0)
    end
    if set -q result[1]
        set -l resolve_cdpath 1
        if contains -- "$tokens[1]" cd cdc
            set resolve_cdpath 0
        else if not set -q tokens[1]; and test "$(count $result)" -eq 1
            set resolve_cdpath 0
        end
        set -l escaped
        for target in $result
            if string match -q -- '$CDPATH/*' "$target"
                set -l name $(string split --max 1 -- '$CDPATH/' "$target")[2]
                set -l selected "$(string escape -n -- "$name")"
                if test -e "$name"; or test "$resolve_cdpath" -eq 1
                    set -l path
                    for root in $CDPATH
                        test -d "$root/$name"; or continue
                        set path "$root/$name"
                        # Prefer a different directory on collisions, if one exists.
                        test "$name" -ef "$path"; or break
                    end
                    if set -q path[1]
                        string match -q -- '/*' "$path"; or set path "$PWD/$path"
                        set path $(aqsnow_fzf_path_alias "$path" | string split0)
                        set selected "$(aqsnow_fzf_path_quote "$path" "$parsed[3]")"
                    end
                end
                set -a escaped "$selected"
            else
                set -a escaped "$(aqsnow_fzf_path_quote "$target" "$parsed[3]")"
            end
        end
        if not set -q tokens[1]
            set -l kind
            set -l execute 0
            for target in $result
                set -l next_kind directory
                if not string match -q -- '$CDPATH/*' "$target"
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
                    if test -d "$target"
                        set next_kind directory
                    else if test -f "$target"
                        set next_kind file
                        if test -x "$target"
                            if not set -q kind[1]; and string match -q -- './*' "$result[1]"
                                set execute 1
                            end
                            set -l header
                            if not read --nchars 2 header 2>/dev/null <"$target"; or test "$header" != '#!'
                                set next_kind executable
                                if not set -q kind[1]; and string match -q -- '*/*' "$result[1]"
                                    set execute 1
                                end
                            end
                        end
                    else
                        set next_kind special
                    end
                end
                if set -q kind[1]; and test "$kind" != "$next_kind"
                    set kind special
                    break
                end
                set kind "$next_kind"
                test "$kind" = special; and break
            end
            test "$(count $result)" -eq 1; or set execute 0
            if test "$kind" = special; or test "$kind" = executable -a "$execute" -eq 0
                set -p escaped file --
            else if test "$(count $result)" -eq 1; and test "$kind" = directory
                set -p escaped cd --
            else if test "$execute" -eq 0
                set -p escaped nvim --
            end
        else if contains -- "$(path basename -- "$tokens[1]")" nvim cd; and not contains -- -- $tokens; and test -z "$parsed[3]"
            if test "$(path basename -- "$tokens[1]")" != nvim; or not contains -- "$tokens[-1]" -u -l -S -s -i -w -W -q -t -c --cmd --listen --server --startuptime
                set -p escaped --
            end
        end
        commandline -rt -- "$(string join -- ' ' $parsed[3]$escaped) "
    end
    commandline -f repaint
end

function aqsnow_fzf_path_quote --argument-names target prefix
    for name in $aqsnow_fzf_diralis
        set -l direnv '$'$name
        test "$name" = HOME; and set direnv '~'
        if test "$target" = "$direnv"; or string match -q -- "$direnv/*" "$target"
            # Tilde expansion only works at the start of a token, not after --option=.
            if test "$direnv" = '~'; and test -n "$prefix"
                set target '$HOME'$(string sub --start 2 -- "$target")
            end
            # Keep the leading $ or ~ expandable; escape everything else.
            string sub --start 2 -- "$(string escape -n -- "$target")"
            return
        end
    end
    string escape -n -- "$target"
end
