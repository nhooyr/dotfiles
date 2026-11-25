function tex --argument-names texfile
    if contains -- "$argv" -h --help
        printf 'Usage: tex MAIN.tex\nBuild and preview a TeX document, then rebuild it when TeX files change.\n'
        return 0
    end
    if test -z "$texfile"; or not test -f "$texfile"
        printf 'Usage: %s %s\n' "$(status function)" '<main.tex>' >&2
        return 1
    end
    set texfile "$(path resolve -- "$texfile")"; or return
    set -l texbase "./$(path basename -- "$texfile")"
    set -l dir "$(path dirname -- "$texfile")"
    cdc "$dir" latexmk -pdf -silent -pv "$texbase"
    set -l last_path
    fswatch -r0 --batch-marker='' -e '.*' -i '\.tex$' "$dir" | while read -zl path
        if test -z "$path"
            set -e last_path
            cdc "$dir" latexmk -pdf -silent "$texbase"
        else
            set path "$(string replace "$dir/" '' "$path")"
            if test "$path" = "$last_path"
                continue
            end
            set last_path "$path"
            printf '%s+%s %s%s\n' "$(set_color --bold)" "$(date '+%X')" "$path" "$(set_color reset)"
        end
    end
    return "$pipestatus[1]"
end
