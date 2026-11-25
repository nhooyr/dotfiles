complete -c reload -f
complete -c reload -n 'test "$(count $(commandline -xpc))" -eq 1' -s h -l help -d 'Show help'
