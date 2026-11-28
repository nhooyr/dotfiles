# Load the prompt lifecycle on its first update; share cache operations with Neovim.
source "$(status dirname)/../git_prompt_cache.fish"

set -g __aqsnow_vcs_directory ''
set -g __aqsnow_vcs_dirty 1
if set -q __aqsnow_vcs_generation
    set -g __aqsnow_vcs_generation "$(math "$__aqsnow_vcs_generation + 1")"
else
    set -g __aqsnow_vcs_generation 0
end

function aqsnow_vcs_prompt_display --argument-names value
    set -g __aqsnow_vcs_prompt "$value"
    # Child processes inherit plain text, while Fish keeps the ANSI styling.
    set -l ansi '\e\[[0-?]*[ -/]*[@-~]|\e[()][A-Za-z0-9]'
    set -gx AQSNOW_FISH_GIT_PROMPT "$(string replace -ra -- "$ansi" '' "$value")"
end

function aqsnow_vcs_prompt_root --argument-names directory
    set directory "$(path resolve -- "$directory")"; or return
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
    if test "$__aqsnow_vcs_directory" = "$PWD"; and test "$__aqsnow_vcs_checked_generation" = "$__aqsnow_vcs_generation"
        return
    end
    set -l previous_directory "$__aqsnow_vcs_directory"
    set -l previous_root "$__aqsnow_vcs_root"
    set -g __aqsnow_vcs_directory "$PWD"
    set -g __aqsnow_vcs_root "$(aqsnow_vcs_prompt_root "$PWD")"
    set -g __aqsnow_vcs_checked_generation "$__aqsnow_vcs_generation"
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
    if set -q __aqsnow_vcs_pending; and set -q __aqsnow_vcs_process
        aqsnow_vcs_prompt_cancel
    end
end

function aqsnow_vcs_prompt_cancel
    functions --erase aqsnow_vcs_prompt_finished
    aqsnow_vcs_prompt_cleanup
    set -e __aqsnow_vcs_pending __aqsnow_vcs_process
    set -g __aqsnow_vcs_dirty 1
end

function aqsnow_vcs_prompt_cleanup --on-event fish_exit
    if set -q __aqsnow_vcs_process
        command kill -TERM "$__aqsnow_vcs_process" 2>/dev/null
    end
    if set -q __aqsnow_vcs_dir
        command rm -rf -- "$__aqsnow_vcs_dir"
        set -e __aqsnow_vcs_dir __aqsnow_vcs_file
    end
end

function aqsnow_vcs_prompt_done
    set -q __aqsnow_vcs_pending; or return
    test -f "$__aqsnow_vcs_file.status"; or return
    set -l previous "$__aqsnow_vcs_prompt"
    set -e __aqsnow_vcs_pending __aqsnow_vcs_process
    set -l code
    set -l identity
    if test -r "$__aqsnow_vcs_file.status"
        read code identity <"$__aqsnow_vcs_file.status"
    end
    if set -q argv[1]
        set code "$argv[1]"
    end
    set -l value "$(string collect < "$__aqsnow_vcs_file")"
    set -l current_root "$(aqsnow_vcs_prompt_root "$__aqsnow_vcs_request_directory")"
    set -l current_identity "$(git_prompt_identity "$current_root")"
    if test "$__aqsnow_vcs_request_generation" != "$__aqsnow_vcs_generation"
        or test "$current_root" != "$__aqsnow_vcs_request_root"
        or test "$identity" != "$current_identity"
        or test "$code" = 75
        # A foreground command or new repository can invalidate even the cache destination.
        set -g __aqsnow_vcs_dirty 1
        set -e __aqsnow_vcs_checked_generation
    else if test "$code" = 0; and test -n "$value"
        git_prompt_cache "$__aqsnow_vcs_request_root" "$value" "$identity" 2>/dev/null
        if test "$status" -eq 75
            set -g __aqsnow_vcs_dirty 1
            set -e __aqsnow_vcs_checked_generation
        else if test "$__aqsnow_vcs_request_root" = "$__aqsnow_vcs_root"; and test "$__aqsnow_vcs_request_directory" = "$PWD"
            aqsnow_vcs_prompt_display "$value"
        end
    else if test "$code" = 0; and test -z "$__aqsnow_vcs_root"; and test "$__aqsnow_vcs_request_directory" = "$PWD"
        aqsnow_vcs_prompt_display ''
    end
    aqsnow_vcs_prompt_cleanup
    if status is-interactive; and test "$__aqsnow_prompt_active" = 1
        git_prompt_ensure
        if test "$previous" != "$__aqsnow_vcs_prompt"
            commandline -f repaint
        end
    end
end

function git_prompt_ensure
    aqsnow_vcs_prompt_restore
    if set -q __aqsnow_vcs_pending
        if not set -q __aqsnow_vcs_process
            return
        end
        if test "$__aqsnow_vcs_request_generation" != "$__aqsnow_vcs_generation"
            or test "$__aqsnow_vcs_request_directory" != "$PWD"
            aqsnow_vcs_prompt_cancel
        else
            return
        end
    end
    set -q __aqsnow_vcs_dirty; or return
    set -g __aqsnow_vcs_dir "$(mktemp -d)"; or return
    set -g __aqsnow_vcs_file "$__aqsnow_vcs_dir/result"
    set -g __aqsnow_vcs_pending 1
    set -g __aqsnow_vcs_request_directory "$PWD"
    set -g __aqsnow_vcs_request_root "$__aqsnow_vcs_root"
    set -g __aqsnow_vcs_request_generation "$__aqsnow_vcs_generation"
    set -e __aqsnow_vcs_dirty
    set -l interpreter "$(status fish-path)"
    GIT_OPTIONAL_LOCKS=0 command "$dotfiles/bin/super" "$interpreter" --no-config -c '
        source "$argv[1]/fish/git_prompt_cache.fish"; or exit
        set -l identity "$(git_prompt_identity "$argv[3]")"
        source "$argv[1]/fish/functions/git_prompt.fish"; or exit
        git_prompt
        set -l code "$status"
        printf "%s %s\n" "$code" "$identity" >"$argv[2].status"; or exit
        exit "$code"
    ' "$dotfiles" "$__aqsnow_vcs_file" "$__aqsnow_vcs_root" </dev/null >"$__aqsnow_vcs_file" 2>/dev/null &
    set -l code "$status"
    if test "$code" -ne 0
        aqsnow_vcs_prompt_cancel
        return "$code"
    end
    if set -q __aqsnow_vcs_pending
        set -g __aqsnow_vcs_process "$last_pid"
        # Keep the job owned for exit events; jobs started in functions do not print completion notices.
        function aqsnow_vcs_prompt_finished --on-process-exit "$__aqsnow_vcs_process"
            test "$argv[2]" = "$__aqsnow_vcs_process"; or return
            functions --erase aqsnow_vcs_prompt_finished
            if test "$argv[3]" -ge 128
                aqsnow_vcs_prompt_cancel
            else if test -f "$__aqsnow_vcs_file.status"
                aqsnow_vcs_prompt_done "$argv[3]"
            else
                aqsnow_vcs_prompt_cancel
            end
        end
    end
end
