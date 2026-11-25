function watchbell --argument-names pattern
    if test -z "$pattern"
        set pattern '.*'
    end
    set -l last_path
    fswatch -r0 --batch-marker='' -e '.*' -i "$pattern" . | while read -zl path
        if test -z "$path"
            set -e last_path
            printf '\a'
        else
            set path "$(string replace "$PWD/" '' "$path")"
            if test "$path" = "$last_path"
                continue
            end
            set last_path "$path"
            if test "$(path basename -- "$path")" = 4913
                continue
            end
            printf '+%s %s\n' "$(date '+%X')" "$path"
        end
    end
    return "$pipestatus[1]"
end
