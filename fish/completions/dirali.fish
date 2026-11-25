complete -c dirali -f
complete -c dirali -n 'test "$(count $(commandline -xpc))" -eq 1' -F
complete -c dirali -n 'test "$(count $(commandline -xpc))" -eq 1' -s h -l help -d 'Show help'
