function cdf --wraps cd --argument-names file
    if test "$(count $argv)" -eq 1; and contains -- "$file" -h --help
        cd "$file"
        return
    end
    CDPATH=. cd -- "$(path dirname -- "$file")"
end
