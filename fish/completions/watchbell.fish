complete -c watchbell -f
complete -c watchbell -n 'test "$(count $(commandline -xpc))" -eq 1' -s h -l help -d 'Show help'
