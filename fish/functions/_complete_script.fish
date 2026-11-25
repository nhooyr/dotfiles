function _complete_script
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
    contains -- "$path" $__aqsnow_script_completion_paths; and return
    set -l arguments "$(string join ' ' -- $(string escape -- "$dotfiles/fish/compgen.pl" "$path"))"
    complete -p "$path" -n 'test -z "$(commandline -ct)"; or string match -q -- "-*" "$(commandline -ct)"; and not contains -- -- $(commandline -xpc)' \
        -a "\$(command perl $arguments)"
    set -ga __aqsnow_script_completion_paths "$path"
end
