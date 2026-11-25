function realpathc --argument-names path --description 'Print and copy an absolute pathname'
    if contains -- "$argv" -h --help
        printf 'Usage: realpathc PATH\nPrint and copy the resolved path to the clipboard.\n'
        return 0
    end
    set -l resolved "$(realpath -- "$path")"; or return
    printf '%s\n' "$resolved" | hpath | pbc
end
