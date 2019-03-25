function fish_prompt
    set -l suffix '$'
    
    if test $USER = root
        set_color af0000
        set suffix '#'
    end
    
    set_color -o

    echo -n (prompt_pwd)
    
    set -l branch_name (branch_name)
    if test -n "$branch_name"
        echo -n :
        echo -n $branch_name
        set -l git_status (git status --porcelain | awk '{print $1}' | uniq)
        if [ (count $git_status) -gt 0 ]
            echo -n :
        end
        for s in $git_status
            echo -n $s
        end
    end
    
    echo
    echo -n "$suffix "
    set_color normal
end

function branch_name
    if not git rev-parse --abbrev-ref HEAD >/dev/null 2>&1
        return
    end

    echo -n (git rev-parse --abbrev-ref HEAD)
end