function fish_prompt
    set -l suffix '$'

    if test $USER = root
        set_color af0000
        set suffix '#'
    end
    
    set_color -o

    set -l branch_name (branch_name)
    echo -n $branch_name
    if test -n "$branch_name"
        echo -n :
    end

    echo -n (prompt_pwd)
    echo -n "$suffix "
    set_color normal

end

function branch_name
    if not git rev-parse --abbrev-ref HEAD >/dev/null 2>&1
        return
    end

    set -l git_status (git status -s 2> /dev/null)
    if test -n "$git_status"
        echo -n \*
    end
    echo -n (git rev-parse --abbrev-ref HEAD)
end