complete -c super -f
complete -c super -n 'test "$(count $(commandline -xpc))" -eq 1' -s h -l help -d 'Show help'
complete -c super -x -a '(__fish_complete_subcommand)'
