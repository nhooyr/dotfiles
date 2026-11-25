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
    if not string match -q '/*' -- "$path"
        set path "$(path resolve -- "$path")"; or return
    end
    contains -- "$path" $compgen_paths; and return
    test -n "$(complete -c "$path")"; and return
    set -l name "$(path basename -- "$tokens[1]")"
    set -l arguments "$(string join ' ' -- $(string escape -- "$dotfiles/fish/compgen.pl" "$path"))"
    # Fish autoloads native completions before evaluating this condition.
    complete -p "$path" -n 'test -z "$(commandline -ct)"; or string match -q -- "-*" "$(commandline -ct)"; and not contains -- -- $(commandline -xpc)' \
        -n "not complete -c $(string escape -- "$name") | string length -q" \
        -a "\$(command perl $arguments)"
    set -ga compgen_paths "$path"
end
