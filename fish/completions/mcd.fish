complete -c mcd -f
complete -c mcd -n 'test "$(count $(commandline -xpc))" -eq 1' -a '(__fish_complete_directories)'
