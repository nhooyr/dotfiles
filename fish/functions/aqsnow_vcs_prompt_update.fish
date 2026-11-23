set -g __aqsnow_vcs_directory "$PWD"
set -g __aqsnow_vcs_dirty 1

# Commands invalidate the cache; changing directories also clears its display.
function aqsnow_vcs_prompt_invalidate --on-event fish_postexec --on-variable PWD
    set -g __aqsnow_vcs_dirty 1
    if test "$__aqsnow_vcs_directory" != "$PWD"
        set -g __aqsnow_vcs_directory "$PWD"
        set -g __aqsnow_vcs_prompt ''
        set -gx AQSNOW_FISH_GIT_PROMPT ''
    end
end

function aqsnow_vcs_prompt_preexec --on-event fish_preexec
    # Background completions must not repaint over a foreground program.
    set -g __aqsnow_prompt_active 0
end

function aqsnow_vcs_prompt_done --on-signal USR1
    set -q __aqsnow_vcs_pending; or return
    test -f "$__aqsnow_vcs_file"; or return
    set -e __aqsnow_vcs_pending
    if test "$__aqsnow_vcs_request_directory" = "$PWD"
        set -g __aqsnow_vcs_prompt "$(string collect < "$__aqsnow_vcs_file")"
        # Child processes inherit plain text, while Fish keeps the ANSI styling.
        set -l ansi '\e\[[0-?]*[ -/]*[@-~]|\e[()][A-Za-z0-9]'
        set -gx AQSNOW_FISH_GIT_PROMPT "$(string replace -ra -- "$ansi" '' "$__aqsnow_vcs_prompt")"
    end
    command rm -f -- "$__aqsnow_vcs_file"
    if status is-interactive; and test "$__aqsnow_prompt_active" = 1
        aqsnow_vcs_prompt_update
        commandline -f repaint
    end
end

function aqsnow_vcs_prompt_update
    set -q __aqsnow_vcs_dirty; or return
    set -q __aqsnow_vcs_pending; and return
    aqsnow_init_rendezvous; or return
    set -e __aqsnow_vcs_dirty
    set -g __aqsnow_vcs_pending 1
    set -g __aqsnow_vcs_request_directory "$PWD"
    set -g __aqsnow_vcs_file "$__aqsnow_rendezvous_dir/vcs-prompt"
    command fish --no-config -c '
        source "$argv[1]"
        fish_vcs_prompt > "$argv[2]"
        test -d "$argv[3]"; and command kill -USR1 "$argv[4]"
    ' "$dotfiles/fish/prompt.fish" "$__aqsnow_vcs_file" \
        "$__aqsnow_rendezvous_dir" "$fish_pid" >/dev/null 2>&1 &
    disown "$last_pid"
end
