function gbp
    argparse --max-args 0 h/help f/force -- $argv; or return
    if set -q _flag_help
        printf '%s\n' 'Usage: gbp [-f|--force]
Fetch and prune all remotes, then delete branches whose upstream is gone.
Use --force to delete branches even when they are not merged.'
        return
    end
    set -l delete_flag -d
    set -q _flag_force; and set delete_flag -D
    for branch in main master
        if git show-ref --verify --quiet "refs/heads/$branch"
            if test "$(git symbolic-ref --quiet HEAD)" != "refs/heads/$branch"
                git switch "$branch"; or return
            end
            break
        end
    end
    git fetch --prune --all
    and git branch -vv |
        awk '$3 ~ /^\[.*:$/ && $4 == "gone]" {printf "%s%c", $1, 0}' |
        xargs -0 -r git branch "$delete_flag" --
end
