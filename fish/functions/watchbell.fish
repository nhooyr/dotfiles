function watchbell --argument-names pattern
    if test -z "$pattern"
        set pattern '.*'
    end
    set -l last_path
    fswatch -r0 --batch-marker='' -e '.*' -i "$pattern" . | while read -zl path
        if test -z "$path"
            if test -n "$last_path"
                printf '\a'
                set -e last_path
            end
        else
            set path "$(string replace "$PWD/" '' "$path")"
            if test "$path" = "$last_path"
                continue
            end
            if test "$(path basename -- "$path")" = 4913
                continue
            end
            set last_path "$path"
            printf '+%s %s\n' "$(date '+%X')" "$path"
        end
    end
    return "$pipestatus[1]"
end
