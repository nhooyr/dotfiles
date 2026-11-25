complete -c tex -f
complete -c tex -n 'test "$(count $(commandline -xpc))" -eq 1' -k -a '(__fish_complete_suffix .tex)'
complete -c tex -n 'test "$(count $(commandline -xpc))" -eq 1' -s h -l help -d 'Show help'
