set -g __aqsnow_vcs_directory ''
set -g __aqsnow_vcs_dirty 1
set -g __aqsnow_vcs_generation 0

function aqsnow_vcs_prompt_display --argument-names value
    set -g __aqsnow_vcs_prompt "$value"
    # Child processes inherit plain text, while Fish keeps the ANSI styling.
    set -l ansi '\e\[[0-?]*[ -/]*[@-~]|\e[()][A-Za-z0-9]'
    set -gx AQSNOW_FISH_GIT_PROMPT "$(string replace -ra -- "$ansi" '' "$value")"
end

function aqsnow_vcs_prompt_root --argument-names directory
    while true
        if test -d "$directory/.git"; or test -f "$directory/.git"
            printf '%s\n' "$directory"
            return
        end
        set -l parent "$(path dirname -- "$directory")"
        test "$parent" != "$directory"; or break
        set directory "$parent"
    end
end

function aqsnow_vcs_prompt_restore
    set -l previous_directory "$__aqsnow_vcs_directory"
    set -l previous_root "$__aqsnow_vcs_root"
    set -g __aqsnow_vcs_directory "$PWD"
    set -g __aqsnow_vcs_root "$(aqsnow_vcs_prompt_root "$PWD")"
    if test "$previous_directory" = "$PWD"; and test "$previous_root" = "$__aqsnow_vcs_root"
        return
    end
    if test -z "$__aqsnow_vcs_root"
        aqsnow_vcs_prompt_display ''
        return
    end
    set -l cached
    if test -r "$__aqsnow_vcs_root/.fish_git_prompt"
        set cached "$(string collect < "$__aqsnow_vcs_root/.fish_git_prompt")"
    end
    if test -n "$cached"
        aqsnow_vcs_prompt_display "$cached"
        return
    end
    if test "$previous_root" = "$__aqsnow_vcs_root"; and test -n "$__aqsnow_vcs_prompt"
        return
    end
    # Reading HEAD avoids running Git before the first prompt, including in linked worktrees.
    set -l git_directory "$__aqsnow_vcs_root/.git"
    if test -f "$git_directory"
        read git_directory <"$git_directory"
        set git_directory "$(string replace -r '^gitdir: ' '' -- "$git_directory")"
        if not string match -q '/*' -- "$git_directory"
            set git_directory "$__aqsnow_vcs_root/$git_directory"
        end
    end
    set -l head
    if test -r "$git_directory/HEAD"
        read head <"$git_directory/HEAD"
    end
    set -l branch git
    if string match -q 'ref: *' -- "$head"
        set branch "$(string replace -r '^ref: (refs/heads/)?' '' -- "$head")"
    else if test -n "$head"
        set branch "$(string sub --length 7 -- "$head")"
    end
    aqsnow_vcs_prompt_display " ($branch)"
end

# A command can initialize, remove, or replace a repository without changing PWD.
function aqsnow_vcs_prompt_invalidate --on-event fish_postexec
    set -g __aqsnow_vcs_generation "$(math "$__aqsnow_vcs_generation + 1")"
    set -g __aqsnow_vcs_dirty 1
    aqsnow_vcs_prompt_restore
end

function aqsnow_vcs_prompt_chdir --on-variable PWD
    set -g __aqsnow_vcs_dirty 1
    aqsnow_vcs_prompt_restore
end

function aqsnow_vcs_prompt_preexec --on-event fish_preexec
    # Background completions must not repaint over a foreground program.
    set -g __aqsnow_prompt_active 0
    set -g __aqsnow_vcs_generation "$(math "$__aqsnow_vcs_generation + 1")"
end

function aqsnow_vcs_prompt_cleanup --on-event fish_exit
    if set -q __aqsnow_rendezvous_dir
        command rm -f -- "$__aqsnow_rendezvous_dir/vcs-alive"
    end
end

function aqsnow_vcs_prompt_done --on-signal USR1
    set -q __aqsnow_vcs_pending; or return
    test -f "$__aqsnow_vcs_file"; or return
    set -e __aqsnow_vcs_pending
    set -l code
    if test -r "$__aqsnow_vcs_file.status"
        read code <"$__aqsnow_vcs_file.status"
    end
    set -l value "$(string collect < "$__aqsnow_vcs_file")"
    set -l current_root "$(aqsnow_vcs_prompt_root "$__aqsnow_vcs_request_directory")"
    if test "$__aqsnow_vcs_request_generation" != "$__aqsnow_vcs_generation"
        or test "$current_root" != "$__aqsnow_vcs_request_root"
        # A foreground command or new repository can invalidate even the cache destination.
        set -g __aqsnow_vcs_dirty 1
    else if test "$code" = 0; and test -n "$value"
        if test -n "$__aqsnow_vcs_request_root"; and test -w "$__aqsnow_vcs_request_root"
            set -l cache "$__aqsnow_vcs_request_root/.fish_git_prompt"
            begin
                set -l saved
                if test -r "$cache"
                    set saved "$(string collect < "$cache")"
                end
                if test "$saved" != "$value"
                    # Keep the temporary file covered by the same Git ignore pattern.
                    set -l temporary "$(command mktemp -d "$__aqsnow_vcs_request_root/.fish-prompt-XXXXXX")"
                    if test -n "$temporary"
                        if printf '%s' "$value" >"$temporary/.fish_git_prompt"
                            command mv -f -- "$temporary/.fish_git_prompt" "$cache"
                        end
                        command rm -f -- "$temporary/.fish_git_prompt"
                        command rmdir -- "$temporary"
                    end
                end
            end 2>/dev/null
        end
        if test "$__aqsnow_vcs_request_root" = "$__aqsnow_vcs_root"; and test "$__aqsnow_vcs_request_directory" = "$PWD"
            aqsnow_vcs_prompt_display "$value"
        end
    else if test "$code" = 0; and test -z "$__aqsnow_vcs_root"; and test "$__aqsnow_vcs_request_directory" = "$PWD"
        aqsnow_vcs_prompt_display ''
    end
    command rm -f -- "$__aqsnow_vcs_file" "$__aqsnow_vcs_file.status"
    if status is-interactive; and test "$__aqsnow_prompt_active" = 1
        aqsnow_vcs_prompt_update
        commandline -f repaint
    end
end

function aqsnow_vcs_prompt_update
    aqsnow_vcs_prompt_restore
    set -q __aqsnow_vcs_dirty; or return
    set -q __aqsnow_vcs_pending; and return
    aqsnow_init_rendezvous; or return
    printf '' >"$__aqsnow_rendezvous_dir/vcs-alive"; or return
    set -e __aqsnow_vcs_dirty
    set -g __aqsnow_vcs_pending 1
    set -g __aqsnow_vcs_request_directory "$PWD"
    set -g __aqsnow_vcs_request_root "$__aqsnow_vcs_root"
    set -g __aqsnow_vcs_request_generation "$__aqsnow_vcs_generation"
    set -l interpreter "$(status fish-path)"
    set -l controller '
        set -l result "$argv[2]/vcs-prompt-$argv[5]"
        set -l control "$argv[2]/vcs-alive"
        printf "" > "$result"; or exit
        while test -f "$control"; and command kill -0 "$argv[3]" 2>/dev/null
            read -l owner < "$control"
            test "$owner" = "$argv[5]"; and break
            command sleep 0.01
        end
        test -f "$control"; and command kill -0 "$argv[3]" 2>/dev/null; or exit
        set -l interpreter "$(status fish-path)"
        command "$interpreter" --no-config -c "$argv[4]" "$argv[1]" "$result.status" > "$result" &
        set -l worker "$last_pid"
        while test -f "$control"; and command kill -0 "$argv[3]" 2>/dev/null; and jobs --query "$worker"
            command sleep 0.05
        end
        if test -f "$control"; and command kill -0 "$argv[3]" 2>/dev/null
            command kill -USR1 "$argv[3]"
        end
        command kill -TERM -- "-$fish_pid"
    '
    # Prompt evaluation suppresses job control, so isolate the controller in a launcher.
    command "$interpreter" --no-config -c '
        status job-control full
        command "$argv[1]" --no-config -c "$argv[2]" "$argv[3]" "$argv[4]" "$argv[5]" "$argv[6]" "$fish_pid" &
        wait "$last_pid"
    ' "$interpreter" "$controller" "$dotfiles/fish/prompt.fish" "$__aqsnow_rendezvous_dir" "$fish_pid" \
        'source "$argv[1]"; and aqsnow_vcs_prompt; set -l code "$status"; printf "%s\n" "$code" > "$argv[2]"' >/dev/null 2>&1 &
    set -l code "$status"
    if test "$code" -ne 0
        set -e __aqsnow_vcs_pending
        return "$code"
    end
    set -l worker "$last_pid"
    set -g __aqsnow_vcs_file "$__aqsnow_rendezvous_dir/vcs-prompt-$worker"
    disown "$worker"
    printf '%s\n' "$worker" >"$__aqsnow_rendezvous_dir/vcs-alive"; or begin
        set -e __aqsnow_vcs_pending
        aqsnow_vcs_prompt_cleanup
        return 1
    end
end
