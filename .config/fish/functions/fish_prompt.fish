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
        set_color blue
        echo -n $branch_name
        set_color normal
        set_color -o
        set -l git_status (git status --porcelain | awk '{print $1}' | sort | uniq)
        if [ (count $git_status) -gt 0 ]
            echo -n :
        end
        for s in $git_status
            switch $s
            case M
                set_color green
            case MM
                set_color red
            case A
                set_color green
            case D
                set_color red
            case R
                set_color green
            case '??'
                set_color red
            end
            echo -n $s
        end
        set_color normal
        set_color -o
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