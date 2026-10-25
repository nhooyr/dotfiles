function multicd
    echo cd "$(string repeat -n "$(math "$(string length -- "$argv")" - 1)" ../)"
end
abbr --add dotdot --regex '^\.\.\.+$' --function multicd
function cdc --wraps cd --argument-names dir
    set -l prevd "$PWD"
    if cd -- "$dir"
        $argv[2..]
        set -l code "$status"
        cd -- "$prevd"; or return
        return "$code"
    else
        return 1
    end
end
function cdf --wraps cd --argument-names file
    cd -- "$(dirname -- "$file")"
end
function up
    if not set -q argv[1]
        cd ..
        return
    end

    if string match --quiet --regex '^[0-9]+$' -- "$argv"
        set -l up (string repeat --count "$argv" ../)
        cd "./$up"
        return
    end

    set -l dir "$PWD"
    while test "$dir" != /
        set dir "$(path dirname -- "$dir")"
        if string match --quiet --regex -- "$argv" "$(path basename -- "$dir")"
            cd -- "$dir"
            return
        end
    end

    printf 'up: no parent dir matches %s\n' "$argv" >&2
    return 1
end
abbrali pd prevd
abbrali bd prevd
abbrali nd nextd
# From embedded:functions/cd.fish @ line 5
# Only change I made is to use cdf and increase MAX_DIR_HIST to 999.
function cd --description 'Change directory'
    set -l MAX_DIR_HIST 999

    # Skip history in subshells.
    if status is-command-substitution
        builtin cd $argv
        return $status
    end

    # Avoid set completions.
    set -l previous $PWD

    if test "$argv" = -
        if test "$__fish_cd_direction" = next
            nextd
        else
            prevd
        end
        return $status
    end

    set -l file $argv
    if test "$argv[1]" = --
        set file $argv[2..]
    end
    if test (count $file) -eq 1; and test -f "$file"
        cdf "$file"
        return
    end

    builtin cd $argv
    set -l cd_status $status

    if test $cd_status -eq 0 -a "$PWD" != "$previous"
        set -q dirprev
        or set -l dirprev
        set -q dirprev[$MAX_DIR_HIST]
        and set -e dirprev[1]

        # If dirprev, dirnext, __fish_cd_direction
        # are set as universal variables, honor their scope.

        set -U -q dirprev
        and set -U -a dirprev $previous
        or set -g -a dirprev $previous

        set -U -q dirnext
        and set -U -e dirnext
        or set -e dirnext

        set -U -q __fish_cd_direction
        and set -U __fish_cd_direction prev
        or set -g __fish_cd_direction prev
    end

    return $cd_status
end
