function _bigfiles --argument-names name
    if contains -- "$argv[2]" -h --help
        set -l kind
        test "$name" != gbigfiles; or set kind 'Git-tracked '
        printf 'Usage: %s\nShow the 16 largest %sfiles by disk usage under the current directory.\n' "$name" "$kind"
        return
    end
    if test "$name" = gbigfiles
        git rev-parse --show-toplevel >/dev/null; or return
    end
    _bigfiles_paths "$name" | gdu -B1 --files0-from=- |
        sort -k1,1nr -k2 |
        head -n 16 |
        gnumfmt --delimiter=\t --field=1 --to=iec
    for code in $pipestatus[1 2 -1]
        test "$code" -eq 0; or return "$code"
    end
end

function _bigfiles_paths --argument-names name
    if test "$name" = gbigfiles
        git ls-files --recurse-submodules --deduplicate -z |
            perl -0ne 'chomp; print "./$_\0" if -f || -l'
        return "$pipestatus[1]"
    end
    command find . '(' -type f -o -type l ')' -print0
    return 0
end
