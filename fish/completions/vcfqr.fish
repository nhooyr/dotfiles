complete -c vcfqr -s h -l help -d 'Show usage'
complete -c vcfqr -f
complete -c vcfqr -n 'test "$(count $(commandline -xpc))" -le 2' -F
