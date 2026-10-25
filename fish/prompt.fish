function fish_prompt
    set -l last_status "$status"
    set -l normal "$(set_color --reset)"
    set -l cwd_color "$(set_color $fish_color_cwd)"
    set -l prompt_status ""

    set -l suffix '$'
    if fish_is_root_user
        set suffix '#'
    end

    if test "$last_status" -ne 0
        set -l status_color "$(set_color brred)"
        set prompt_status ' ['"$status_color$last_status$normal"']'
        set suffix "$status_color$suffix"
    end

    echo -s "$(prompt_login) $cwd_color$(prompt_pwd)$normal$(fish_vcs_prompt)$normal$prompt_status"
    echo -n -s "$(set_color --bold)"'['"$suffix$(set_color --reset --bold)"']'"$normal "
end
set -g fish_prompt_pwd_dir_length 0
set -g fish_color_user --reset
if fish_is_root_user
    set -g fish_color_user brred --underline --bold --italic
end
set -g fish_color_cwd blue
set -g fish_color_host --underline
set -g fish_color_host_remote cyan --underline
function prompt_hostname
    if set -q SSH_TTY
        echo $hostname
    else
        string replace -r -- "\..*" "" $hostname
    end
end
function fish_right_prompt
    set_color magenta --italic
    date '+%X'
    set_color --reset
end
function fish_title
    set -l ssh
    if set -q SSH_TTY
        set ssh "[$(prompt_hostname | string sub -l 10)] "
    end
    if set -q argv[1]
        echo -- "$ssh$(string sub -l 20 -- "$argv[1]") $(prompt_pwd)"
    else
        set -l command "$(status current-command | string sub -l 20) "
        if test "$command" = "fish "
            set command
        end
        echo -- "$ssh$command$(prompt_pwd)"
    end
end
function fish_mode_prompt
    if not contains -- "$fish_key_bindings" fish_vi_key_bindings fish_hybrid_key_bindings
        return
    end
    set_color --bold
    switch $fish_bind_mode
        case default
            set_color blue
            echo '[N]'
        case insert
            set_color green
            echo '[I]'
        case replace_one
            set_color green
            echo '[R]'
        case replace
            set_color cyan
            echo '[R]'
        case visual
            set_color magenta
            echo '[V]'
        case operator f F t T
            set_color cyan
            echo '[N]'
    end
    set_color --reset
    echo -n ' '
end
set -g __fish_git_prompt_showdirtystate true
set -g __fish_git_prompt_showuntrackedfiles true
set -g __fish_git_prompt_showupstream informative
set -g __fish_git_prompt_showstashstate true
set -g __fish_git_prompt_color_branch --underline
set -g __fish_git_prompt_color_flags cyan
set -g __fish_git_prompt_color_merging --italic
