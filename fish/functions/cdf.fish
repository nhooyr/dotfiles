function cdf --wraps cd --argument-names file
    if not set -q argv[1]
        printf 'Usage: %s <file>\n' "$(status function)" >&2
        return 1
    end
    if test "$(count $argv)" -eq 1; and contains -- "$file" -h --help
        cd "$file"
        return
    end
    CDPATH=. cd -- "$(path dirname -- "$file")"
end
