complete -c note -f
complete -c note -n 'test "$(count $(commandline -xpc))" -eq 1' -s h -l help -d 'Show help'
