function __fish_up_parents
    set -l directory "$PWD"
    while test "$directory" != /
        set directory "$(path dirname -- "$directory")"
        string escape --style=regex -- "$(path basename -- "$directory")"
    end
end

complete -c up -f
complete -c up -n 'test "$(count $(commandline -xpc))" -eq 1' -a '(__fish_up_parents)' -d 'Parent directory'
complete -c up -n 'test "$(count $(commandline -xpc))" -eq 1' -s h -l help -d 'Show help'
