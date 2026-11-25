complete -c sshv -f
complete -c sshv -n 'test "$(count $(commandline -xpc))" -eq 1' -a '(__fish_complete_user_at_hosts)' -d 'Remote server'
complete -c sshv -n 'test "$(count $(commandline -xpc))" -eq 1' -s h -l help -d 'Show help'
