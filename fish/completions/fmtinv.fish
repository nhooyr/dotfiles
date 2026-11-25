complete -c fmtinv -f
complete -c fmtinv -n 'test "$(count $(commandline -xpc))" -eq 1' -F
complete -c fmtinv -n 'test "$(count $(commandline -xpc))" -eq 1' -a - -d 'Read invoice from standard input'
