function aqsnow_fzf_path_alias --argument-names target
    set -l aliased "$target"
    set -l longest 0
    for name in $aqsnow_fzf_diralis
        test -d "$$name"; or continue
        set -l directory $(path dirname -Z -- "$$name/." | string split0)
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
