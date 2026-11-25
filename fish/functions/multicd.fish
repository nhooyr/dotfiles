function multicd
    if contains -- "$argv" -h --help
        printf '%s\n' 'Usage: multicd DOTS' 'Print a cd command with one parent level per dot beyond the first.'
        return
    end
    echo cd -- "$(string repeat -n "$(math "$(string length -- "$argv")" - 1)" ../)"
end
