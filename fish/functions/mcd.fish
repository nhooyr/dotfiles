function mcd --wraps 'mkdir -p'
    if test "$(count $argv)" -ne 1
        printf 'Usage: %s <directory>\n' "$(status function)" >&2
        return 1
    end
    mkdir -p -- "$argv"; or return
    cd -- "$argv"
end
