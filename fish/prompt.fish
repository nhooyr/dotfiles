function fish_prompt
    set -l last_status "$status"
    set -l normal "$(set_color --reset)"
    set -l status_color "$(set_color brgreen)"
    set -l cwd_color "$(set_color $fish_color_cwd)"
    set -l prompt_status ""

    set -l suffix '[$]'
    if fish_is_root_user
        set suffix "$(set_color brred)"'[#]'
    end

    if test "$last_status" -ne 0
        set status_color "$(set_color brred --underline --bold --theme=default)"
        set prompt_status " $status_color"'['"$last_status"']'"$normal"
        set suffix "$(set_color brred --underline)$suffix"
    end

    echo -s "$(prompt_login) $cwd_color$(prompt_pwd)$normal$(fish_vcs_prompt)$normal$prompt_status"
    echo -n -s "$(set_color --bold --underline --italic)$suffix$normal "
end
set -g fish_prompt_pwd_dir_length 0
set -g __fish_git_prompt_show_informative_status true
set -g fish_color_user --reset --theme=default
if fish_is_root_user
    set -g fish_color_user brred --underline --bold --italic --theme=default
end
set -g fish_color_cwd blue --theme=default
set -g fish_color_host --underline --theme=default
set -g fish_color_host_remote cyan --underline --theme=default
function prompt_hostname
    if set -q SSH_TTY
        hostname
    else
        string replace -r -- "\..*" "" $hostname
    end
end
function fish_right_prompt
    set_color magenta --italic --theme=default
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
    switch $fish_bind_mode
        case default
            set_color --bold blue
            echo '[N]'
        case insert
            set_color --bold green
            echo '[I]'
        case replace_one
            set_color --bold green
            echo '[R]'
        case replace
            set_color --bold cyan
            echo '[R]'
        case visual
            set_color --bold magenta
            echo '[V]'
        case operator f F t T
            set_color --bold cyan
            echo '[N]'
    end
    set_color --reset
    echo -n ' '
end
