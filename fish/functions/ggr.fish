function ggr --description 'Replace text in Git-tracked files' --argument-names pattern replacement
    set -l usage 'Usage: ggr PATTERN REPLACEMENT [PATHSPEC ...]
Replace extended regular expression matches using sed replacement syntax.
Lowercase patterns ignore case. Original files are saved with a .bak suffix.'
    if contains -- "$pattern" -h --help
        printf '%s\n' "$usage"
        return 0
    end
    if not set -q argv[2]
        printf '%s\n' "$usage" >&2
        return 2
    end

    set -l ignore_case
    set -l flags g
    if __grep_smart_case -- "$pattern"
        set ignore_case -i
        set flags gi
    end
    gg -lz $ignore_case -e "$pattern" -- $argv[3..] |
        xargs -0 -r sed -i.bak -Ee 's'\x1F"$pattern"\x1F"$replacement"\x1F"$flags" --
end
