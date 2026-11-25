complete -c realpathc -f
complete -c realpathc -n 'test "$(count $(commandline -xpc))" -eq 1' -F
complete -c realpathc -n 'test "$(count $(commandline -xpc))" -eq 1' -s h -l help -d 'Show help'
