complete -c dotln -f
complete -c dotln -n 'test "$(count $(commandline -xpc))" -le 2' -F
