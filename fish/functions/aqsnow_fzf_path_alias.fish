function aqsnow_fzf_path_alias --argument-names target
    set -l aliased "$target"
    set -l longest 0
    for name in $aqsnow_fzf_diralis
        set -l source "$$name"
        string match -q '/*' -- "$source"; or set source "$PWD/$source"
        set -l cache __aqsnow_fzf_dirali_$name
        set -l paths $$cache
        # Registration also clears the cache after an alias is retargeted.
        if not set -q paths[1]; or test "$paths[1]" != "$source"
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
            if string match -qr -- '^'$(string escape --style=regex -- "$directory")'(/|$)' "$target"
                set -l direnv '$'$name
                test "$name" = HOME; and set direnv '~'
                set -l suffix $(string split --max 1 -- "$directory" "$target")[2]
                set aliased "$direnv$suffix"
                set longest "$length"
            end
        end
    end
    printf '%s\0' "$aliased"
end
