function noti --wraps time
    time $argv
    set -l code "$status"
    printf '\a'
    return "$code"
end
