function ghop --wraps 'gh pr view' --description 'Open the branch pull request, or start creating one'
    set -l args $argv
    argparse --ignore-unknown R/repo= -- $argv; or return
    set -l output "$(gh pr view --web $args 2>&1)"
    set -l code "$status"
    if test "$code" -eq 0
        test -z "$output"; or printf '%s\n' "$output"
    else if not set -q argv[1]; and string match -q -- 'no pull requests found*' "$output"
        ghep $args
        return
    else
        printf '%s\n' "$output" >&2
    end
    return "$code"
end
