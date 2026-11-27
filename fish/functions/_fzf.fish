source "$(status dirname)/../fzf_upstream.fish"; or return

function _fzf --argument-names widget
    if test "$widget" = fzf-path-first-widget
        fzf_path_widget "$widget"; or return 1
    else if test "$widget" = fzf-history-first-widget
        fzf-history-widget --first; or return 1
    else
        rendezvous_init; or return
        # Indices preserve fzf's empty-selection guard without copying filenames.
        set -l action "alt-enter:execute-silent(test -n '{+n}'; and printf exec > $(string escape -- "$RENDEZVOUS_FISH"))+accept"
        set -l option "--bind=$(string escape -- "$action")"

        for name in FZF_CTRL_R_OPTS FZF_CTRL_T_OPTS FZF_ALT_C_OPTS FZF_COMPLETION_OPTS FZF_EXPANSION_OPTS
            set --function --export "$name" "$$name $option"
        end

        if contains -- "$widget" fzf-file-widget fzf-cd-widget fzf-path-widget fzf-recent-widget
            fzf_path_widget "$widget"
        else
            $widget
        end
        or return 1
        rendezvous
    end
    if test "$fish_bind_mode" != insert
        set -g fish_bind_mode insert
    end
    return 0
end

function _fzf_select --argument-names widget query
    if contains -- "$widget" fzf-path-first-widget fzf-history-first-widget
        fzf --filter="$query" | read --null --local result
        and printf '%s\0' "$result"
    else
        fzf --query="$query"
    end
end

function fzf_path_widget --argument-names widget
    set -l parsed $(__fzf_parse_commandline | string split0)
    set -l dir "$parsed[1]"
    set -l token "$(string replace -- "$parsed[3]" '' "$(commandline --current-token --tokens-expanded)")"
    # A bare / selects global roots; only ./ requests a full home-directory scan.
    if test "$token" = /
        set dir ''
    else if test "$dir" -ef ~; and not string match -q -- './*' "$token"
        set dir ''
    end
    set -l global_alias ''
    set -l tokens $(commandline --cut-at-cursor --current-process --tokens-expanded)
    set -l modifier
    while contains -- "$tokens[1]" and or not '!' command builtin exec time if while else --; or string match -qr '^[[:alnum:]_]+=' -- "$tokens[1]"
        contains -- "$tokens[1]" command builtin exec; and set modifier "$tokens[1]"
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
    if not set -q tokens[1]; and not string match -q -- '/*' "$token"
        set flags --keep-dot
    end

    set -l dirs
    for name in $aqsnow_fzf_diralis
        test -d "$$name"; or continue
        set -l direnv '$'$name
        test "$name" = HOME; and set direnv '~'
        set -a dirs --dirali "$direnv" "$$name"
        test "$name" = nhooyr; and set global_alias "$direnv"
    end

    set -l shell $(string join ' ' -- $(string escape -- $(status fish-path) -c))
    # Ignore the leading $ and suffix; \x1f is the invisible marker for ordinary files.
    set -lx FZF_DEFAULT_OPTS $(__fzf_defaults \
        '--reverse --scheme=path --delimiter="^[$]|[/*=>@|\\\\x1f]$" --nth=2,.. --accept-nth=..' \
        "$opts --ansi --read0 --print0 --with-shell=$(string escape -- "$shell")")
    set -lx FZF_DEFAULT_OPTS_FILE
    set -l query "$parsed[2]"
    # Path widgets keep ./ in the query to select explicit local paths.
    if test "$widget" != fzf-recent-widget; and string match -q -- './*' "$token"
        contains -- "$widget" fzf-path-widget fzf-path-first-widget; and set query "$token"
        set global_alias ''
    else if not contains -- "$widget" fzf-file-widget fzf-recent-widget
        set -a flags --cdpath "$CDPATH"
    end
    set -l result
    if test "$widget" = fzf-recent-widget
        set result $(command nvim --headless -u NONE -n \
            -c 'lua for _, path in ipairs(vim.v.oldfiles) do if path:sub(1, 1) == "/" then io.write(path, "\0") end end; vim.o.shadafile = "NONE"' -c 'qa!' \
            | fzfp --read0 --color --classify $flags $dirs -- . '' -f \
            | _fzf_select "$widget" "$query" | string split0)
    else
        set result $(fzfp --color --classify $flags $dirs -- "$dir" "$global_alias" "$type" | _fzf_select "$widget" "$query" | string split0)
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
                        set path $(dirali "$path" | string split0)
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
                            if not set -q kind[1]
                                if test "$widget" = fzf-path-first-widget
                                    or string match -q -- './*' "$result[1]"; or string match -q -- '/*' "$token"
                                    set execute 1
                                end
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
                    if contains -- "$kind" directory file; and contains -- "$next_kind" directory file
                        set next_kind file
                    else
                        set kind special
                        break
                    end
                end
                set kind "$next_kind"
                test "$kind" = special; and break
            end
            test "$(count $result)" -eq 1; or set execute 0
            if test "$execute" -eq 1 -a "$widget" = fzf-path-first-widget
                and not string match -q -- '/*' "$target"
                and not string match -q -- './*' "$result[1]"
                set escaped "$(aqsnow_fzf_path_quote "./$result[1]" "$parsed[3]")"
            end
            if test "$execute" -eq 1; and string match -q -- '/*' "$token"
                if not string match -q -- '/*' "$target"
                    set target "$PWD/$(string replace --regex -- '^\./' '' "$target")"
                end
                set -l aliased "$(dirali "$target" | string split0)"
                set escaped "$(aqsnow_fzf_path_quote "$aliased" "$parsed[3]")"
            end
            set -l default_command
            if test "$kind" = special; or test "$kind" = executable -a "$execute" -eq 0
                set default_command file
            else if test "$(count $result)" -eq 1; and test "$kind" = directory
                set default_command cd
            else if test "$execute" -eq 0
                set default_command nvim
            end
            if set -q default_command[1]
                set -p escaped "$default_command" --
            end
            if test "$default_command" = cd; and contains -- "$modifier" command exec
                or test "$modifier" = builtin -a "$default_command" != cd
                set -l process "$(commandline -p)"
                set -l cursor "$(commandline -Cp)"
                set -l length "$(string length -- "$(commandline -ct)")"
                set -l prefix "$(string sub --length "$(math "$cursor - $length")" -- "$process")"
                set -l adjusted "$(string replace --regex -- '(^|[[:space:]])'"$modifier"'[[:space:]]+(?:--[[:space:]]+)?$' '$1' "$prefix")"
                commandline -rp -- "$(string replace -- "$prefix" "$adjusted" "$process")"
                commandline -Cp "$(math "$cursor - $(string length -- "$prefix") + $(string length -- "$adjusted")")"
            end
        else if contains -- "$(path basename -- "$tokens[1]")" nvim cd; and not contains -- -- $tokens; and test -z "$parsed[3]"
            if test "$(path basename -- "$tokens[1]")" != nvim; or not contains -- "$tokens[-1]" -u -l -S -s -i -w -W -q -t -c --cmd --listen --server --startuptime
                set -p escaped --
            end
        end
        commandline -rt -- "$(string join -- ' ' $parsed[3]$escaped) "
    end
    commandline -f repaint
    set -q result[1]
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
