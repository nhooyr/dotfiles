function aqsnow_vcs_prompt_cache --argument-names root value
    if test -z "$root"; or not test -w "$root"
        return
    end
    set -l cache "$root/.fish_git_prompt"
    set -l saved
    if test -r "$cache"
        set saved "$(string collect < "$cache")"
    end
    if test "$saved" = "$value"
        return
    end
    # Keep the temporary file covered by the same Git ignore pattern.
    set -l temporary "$(command mktemp -d "$root/.fish-prompt-XXXXXX")"
    if test -n "$temporary"
        if printf '%s' "$value" >"$temporary/.fish_git_prompt"
            command mv -f -- "$temporary/.fish_git_prompt" "$cache"
        end
        command rm -f -- "$temporary/.fish_git_prompt"
        command rmdir -- "$temporary"
    end
end
