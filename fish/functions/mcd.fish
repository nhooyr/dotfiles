function mcd --wraps 'mkdir -p'
    if test "$(count $argv)" -ne 1
        printf 'Usage: %s <directory>\n' "$(status function)" >&2
        return 1
    end
    if contains -- "$argv[1]" -h --help
        mkdir -p "$argv"
        return
    end
    mkdir -p -- "$argv"; or return
    cd -- "$argv"
end
