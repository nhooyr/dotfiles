function cdpath_add
    argparse --exclusive p,a,b p/prepend a/after= b/before= -- $argv; or return
    set -l index "$(count $CDPATH)"
    set -q _flag_prepend; and set index 0
    set -l anchor $_flag_before $_flag_after
    if set -q anchor[1]
        set index "$(contains -i -- "$anchor" $CDPATH)"
        if test -z "$index"
            printf '%s: %s is not in CDPATH\n' "$(status function)" "$(string escape -- "$anchor")" >&2
            return 1
        end
        set -q _flag_before; and set index "$(math "$index - 1")"
    end

    set -l paths
    for path in $argv
        if test -n "$path"; and not contains -- "$path" $CDPATH $paths
            set -a paths "$path"
        end
    end
    set -q paths[1]; or return 0
    set -l head
    test "$index" -gt 0; and set head $CDPATH[..$index]
    set -l next_index "$(math "$index + 1")"
    set --path -g CDPATH $head $paths $CDPATH[$next_index..]
end
cdpath_add . "$dotfiles" "$notes" "$nhooyr" ~/code ~

abbr --add dotdot --regex '^\.\.\.+$' --function multicd
abbrali pd prevd
abbrali bd prevd
abbrali nd nextd
abbrali md mkdir -p
abbrali mcdt 'cd -- "$(mktemp -d)"'

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
