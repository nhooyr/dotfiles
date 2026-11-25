function git_log --wraps 'git log'
    command git log $argv
    set -l code "$status"
    # Quitting the pager may close the pipe before Git finishes.
    test "$code" -eq 141; and return 0
    return "$code"
end
