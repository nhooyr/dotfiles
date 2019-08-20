set -g fish_prompt_pwd_dir_length 0

function fish_prompt
    set -l suffix '$'
    set -l user
    
    if [ "$USER" = root ]
        set_color red
        set suffix '#'
    else if [ "$USER" != nhooyr ]
        set user 1
        echo -n "$USER"
    end
    
    set_color -o

    if ! echo "$hostname" | grep -q ien
        if [ -n "$user" ]
            echo -n @
        end
        echo -n (prompt_hostname):
    else if [ -n "$user" ]
        echo -n :
    end

    echo -n (prompt_pwd)
    
    git_info
    
    set_color -o
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

function git_info
    set -l branch (branch_name)
    if [ -z "$branch" ]
        return
    end

    echo -n :
    set_color blue
    echo -n "$branch"

    git status --porcelain | read -z git_status
    if [ -n "$git_status" ]
        set_color cyan
        echo -n "*"
    end

    # git stash list takes 100ms for some reason. git status is very fast.
    if git status --show-stash | grep -qs "Your stash currently has"
        set_color green
        echo -n "&"
    end

    set_color normal
end
