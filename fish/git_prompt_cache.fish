# Shared cache operations, sourced by the Fish prompt and Neovim when needed.
function git_prompt_identity --argument-names root
    test -n "$root"; or return
    command perl -e '
        my $git = "$ARGV[0]/.git";
        if (-f $git) {
            open my $file, "<", $git or exit;
            my $target = <$file> // "";
            chomp $target;
            exit unless $target =~ s/\Agitdir: //;
            $git = $target =~ m{\A/} ? $target : "$ARGV[0]/$target";
        }
        my @s = stat $git;
        print "$s[0]:$s[1]" if @s;
    ' "$root"
end

function git_prompt_cache --argument-names root value identity
    if test -z "$root"
        return
    end
    set -l cache "$root/.fish_git_prompt"
    set -l saved
    if test -r "$cache"
        set saved "$(string collect < "$cache")"
    end
    # Keep the temporary file covered by the same Git ignore pattern.
    set -l temporary
    set -l ready 0
    if test "$saved" != "$value"; and test -w "$root"
        set temporary "$(command mktemp -d "$root/.fish-prompt-XXXXXX")"
        if test -n "$temporary"; and printf '%s' "$value" >"$temporary/.fish_git_prompt"
            set ready 1
        end
    end
    set -l code 0
    if test -n "$identity"; and test "$identity" != "$(git_prompt_identity "$root")"
        set code 75
    else if test "$ready" -eq 1
        command mv -f -- "$temporary/.fish_git_prompt" "$cache"
    end
    if test -n "$temporary"
        command rm -f -- "$temporary/.fish_git_prompt"
        command rmdir -- "$temporary"
    end
    return "$code"
end
