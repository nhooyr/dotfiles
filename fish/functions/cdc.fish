function cdc --wraps cd --argument-names dir
    set -l prevd "$PWD"
    if cd -- "$dir"
        test "$(count $argv)" -lt 2; and return 0
        $argv[2..]
        set -l code "$status"
        cd -- "$prevd"; or return
        return "$code"
    else
        return 1
    end
end
