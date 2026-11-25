complete -c cdf -f
complete -c cdf -n 'test "$(count $(commandline -xpc))" -eq 1' -a '(__fish_complete_path)'
