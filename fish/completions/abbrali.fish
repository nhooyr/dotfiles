complete -c abbrali -f
complete -c abbrali -n 'test "$(count $(commandline -xpc))" -ge 2' -x -a '(__fish_complete_subcommand --fcs-skip=2)'
