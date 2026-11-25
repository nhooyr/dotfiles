complete -c biglines -f
complete -c biglines -n 'test "$(count $(commandline -xpc))" -eq 1' -F -a - -d 'Read standard input'
complete -c biglines -n 'test "$(count $(commandline -xpc))" -eq 1' -s h -l help -d 'Show help'
