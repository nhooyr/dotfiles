complete -c npass -f
complete -c npass -n 'test "$(count $(commandline -xpc))" -eq 1' -a 20 -d 'Password length (default: 20; range: 5–9999)'
