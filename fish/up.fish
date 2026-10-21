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
