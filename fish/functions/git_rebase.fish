function git_rebase --wraps 'git rebase'
    if test "$(count $argv)" -eq 1
        and contains -- "$argv[1]" -i --interactive
        for base in main master
            if command git show-ref --verify --quiet "refs/heads/$base"
                set -a argv "$base"
                break
            end
        end
    end
    command git rebase $argv
end
