function multicd
    echo cd "$(string repeat -n "$(math "$(string length -- "$argv")" - 1)" ../)"
end
abbr --add dotdot --regex '^\.\.\.+$' --function multicd
function cdc --wraps cd --argument-names dir
    if test "$(count $argv)" -lt 2
        echo "cdc: <dir> <cmd>" >&2
        return 1
    end
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
    CDPATH=. cd -- "$(path dirname -- "$file")"
end
function up
    if not set -q argv[1]
        cd ..
        return
    end

    string replace -rq -- "$argv" '' '' 2>/dev/null
    if test "$status" -eq 2
        echo "up: invalid regex" >&2
        return 1
    end

    if string match -qr '^[0-9]+$' -- "$argv"
        set -l up "$(string repeat --count "$argv" ../)"; or return
        cd "./$up"
        return
    end

    set -l dir "$PWD"
    while test "$dir" != /
        set dir "$(path dirname -- "$dir")"
        set -l pattern "$argv"
        set -l target "$(path basename -- "$dir")"
        if string match -q '*/*' -- "$argv"
            set pattern "(?:$argv)\$"
            set target "$dir"
        end
        if string replace -rq -- "$pattern" '' "$target"
            cd -- "$dir"
            return
        end
    end

    printf '%s: no parent dir matches %s\n' "$(status function)" "$argv" >&2
    return 1
end
abbrali pd prevd
abbrali bd prevd
abbrali nd nextd
function mcd --wraps 'mkdir -p'
    mkdir -p -- "$argv"; or return
    cd -- "$argv"
end

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
    if test "$(count $file)" -eq 1; and test -f "$file"
        cdf "$file"
        return
    end

    builtin cd $argv
    set -l cd_status $status

    if test "$cd_status" -eq 0; and test "$PWD" != "$previous"
        set -q dirprev; or set -l dirprev
        set -q dirprev[$MAX_DIR_HIST]; and set -e dirprev[1]

        # If dirprev, dirnext, __fish_cd_direction
        # are set as universal variables, honor their scope.

        set -U -q dirprev; and set -U -a dirprev $previous; or set -g -a dirprev $previous

        set -U -q dirnext; and set -U -e dirnext; or set -e dirnext

        set -U -q __fish_cd_direction; and set -U __fish_cd_direction prev; or set -g __fish_cd_direction prev
    end

    return $cd_status
end
