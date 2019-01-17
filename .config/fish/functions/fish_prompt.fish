function fish_prompt
    set -l color_user $fish_color_user
    set -l color_host $fish_color_host
    set -l color_cwd $fish_color_cwd
    if who am i | grep -q '('
        set color_user 6d034a
        set color_host green
        set color_cwd blue
    end
    set -l suffix '$'

    if test $USER = root
        set -l color_root af0000
        if who am i | grep -q '('
            set color_root brmagenta
        end

        set color_user $color_root
        set color_host $color_root
        set color_cwd $color_root
        set suffix '#'
    end

    set_color $color_user
    echo -n $USER
    set_color normal
    echo -n @
    set_color $color_host
    echo -n (prompt_hostname)
    set_color normal
    echo -n :

    set -l branch_name (branch_name)
    echo -n $branch_name
    if test -n "$branch_name"
        echo -n :
    end

    set_color $color_cwd
    prompt_pwd
    set_color normal
    echo -n "$suffix "
end

function branch_name
    if not git rev-parse --abbrev-ref HEAD >/dev/null 2>&1
        return
    end

    set -l color_branch af5fd7
    if who am i | grep -q '('
        set color_branch ff005f
    end

    if test $USER = root
        set color_branch af0000
        if who am i | grep -q '('
            set color_branch brmagenta
        end
    end

    set -l git_status (git status -s 2> /dev/null)
    set_color $color_branch
    if test -n "$git_status"
        echo -n \*
    end
    echo -n (git rev-parse --abbrev-ref HEAD)
    set_color normal
end