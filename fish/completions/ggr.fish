complete -c ggr -f
complete -c ggr -n 'test "$(count $(commandline -xpc))" -eq 1' -s h -l help -d 'Show help'
complete -c ggr -n 'test "$(count $(commandline -xpc))" -ge 3' -F
