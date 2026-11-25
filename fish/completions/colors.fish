complete -c colors -f
complete -c colors -n 'test "$(count $(commandline -xpc))" -eq 1' -s h -l help -d 'Show help'
