function realpathc --argument-names path --description 'Print and copy an absolute pathname'
    set -l resolved "$(realpath -- "$path")"; or return
    printf '%s\n' "$resolved" | hpath | pbc
end
