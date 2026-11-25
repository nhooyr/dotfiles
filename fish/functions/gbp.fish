function gbp
    argparse --max-args 0 f/force -- $argv; or return
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
