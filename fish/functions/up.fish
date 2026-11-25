function up
    if contains -- "$argv" -h --help
        printf 'Usage: up [COUNT|PATTERN]\nGo up COUNT directories, or to the nearest parent matching PATTERN.\nWith no argument, go up one directory.\n'
        return 0
    end
    if not set -q argv[1]
        cd ..
        return
    end

    string replace -rq -- "$argv" '' '' 2>/dev/null
    if test "$status" -eq 2
        printf '%s: invalid regex\n' "$(status function)" >&2
        return 1
    end

    if string match -qr '^[0-9]{1,4}$' -- "$argv"
        test "$argv" -eq 0; and return 0
        set -l up "$(string repeat --count "$argv" ../)"; or return
        cd -- "./$up"
        return
    end

    set -l pattern "$argv"
    if string match -q '*/*' -- "$pattern"
        set pattern "(?:$pattern)\$"
    end

    set -l dir "$PWD"
    while test "$dir" != /
        set dir "$(path dirname -- "$dir")"
        set -l target "$dir"
        if not string match -q '*/*' -- "$pattern"
            set target "$(path basename -- "$dir")"
        end
        if string replace -rq -- "$pattern" '' "$target"
            cd -- "$dir"
            return
        end
    end

    printf '%s: no parent dir matches %s\n' "$(status function)" "$argv" >&2
    return 1
end
