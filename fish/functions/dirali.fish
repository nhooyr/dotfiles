function dirali --argument-names target
    set -l aliased "$target"
    set -l longest 0
    for name in $aqsnow_fzf_diralis
        set -l source "$$name"
        test -n "$source"; or continue
        if not string match -q '/*' -- "$source"
            printf 'dirali: alias %s requires an absolute path: %s\n' "$name" "$source" >&2
            return 1
        end
        set -l cache __aqsnow_fzf_dirali_$name
        set -l paths $$cache
        # Registration also clears the cache after an alias is retargeted.
        if not set -q paths[1]
            or test "$paths[1]" != "$source"
            or test -n "$paths[3]" -a ! "$source" -ef "$paths[3]"
            test -d "$$name"; or continue
            set -l directory $(path dirname -Z -- "$source/." | string split0)
            set -l resolved "$(path resolve -- "$directory")"; or continue
            set paths "$source" "$directory"
            test "$resolved" = "$directory"; or set -a paths "$resolved"
            set -g "$cache" $paths
        end
        for directory in $paths[2..]
            set -l length $(string length -- "$directory")
            test "$length" -gt "$longest"; or continue
            set -l pattern '^'$(string escape --style=regex -- "$directory")
            test "$directory" = /; or set pattern "$pattern"'(/|$)'
            if string match -qr -- "$pattern" "$target"
                set -l direnv '$'$name
                test "$name" = HOME; and set direnv '~'
                set -l suffix $(string split --max 1 -- "$directory" "$target")[2]
                if test "$directory" = /; and test -n "$suffix"
                    set suffix "/$suffix"
                end
                set aliased "$direnv$suffix"
                set longest "$length"
            end
        end
    end
    printf '%s\0' "$aliased"
end
