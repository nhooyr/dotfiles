function compgen
    if contains -- "$argv" -h --help
        printf 'Usage: compgen\nRegister cached flag completions for the current local script.\n'
        return 0
    end
    set -l token "$(commandline -ct)"
    test -z "$token"; or string match -q -- '-*' "$token"; or return
    set -l tokens $(commandline -xpc)
    contains -- -- $tokens; and return
    set -l path "$tokens[1]"
    string match -q '*/*' -- "$path"; or return
    test -f "$path"; and test -x "$path"; or return
    set -l name "$(path basename -- "$path")"
    if not string match -q '/*' -- "$path"
        set path "$(path resolve -- "$path")"; or return
    end
    contains -- "$path" $compgen_paths; and return
    test -n "$(complete --color never -c "$name" -c "$path")"; and return
    for directory in $fish_complete_path
        if test -f "$directory/$name.fish"
            source "$directory/$name.fish"
            return
        end
    end
    if set -l definition "$(status get-file "completions/$name.fish" 2>/dev/null)"
        printf '%s\n' "$definition" | source
        return
    end
    set -l arguments "$(string join ' ' -- $(string escape -- "$dotfiles/fish/compgen.pl" "$path"))"
    complete -p "$path" -n 'test -z "$(commandline -ct)"; or string match -q -- "-*" "$(commandline -ct)"; and not contains -- -- $(commandline -xpc)' \
        -a "\$(command perl $arguments)"
    set -ga compgen_paths "$path"
end
