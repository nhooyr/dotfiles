function aqsnow_vcs_prompt_cache --argument-names root value identity
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
            if test -z "$identity"
                or test "$identity" = "$(command perl -e 'my @s = stat "$ARGV[0]/.git"; print "$s[0]:$s[1]" if @s' "$root")"
                command mv -f -- "$temporary/.fish_git_prompt" "$cache"
            end
        end
        command rm -f -- "$temporary/.fish_git_prompt"
        command rmdir -- "$temporary"
    end
end
