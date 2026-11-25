complete -c cdpath_add -f
complete -c cdpath_add -s h -l help -d 'Show help'
complete -c cdpath_add -s p -l prepend -d 'Insert at the beginning of CDPATH'
complete -c cdpath_add -s a -l after -x -a '$CDPATH' -d 'Insert after this CDPATH entry'
complete -c cdpath_add -s b -l before -x -a '$CDPATH' -d 'Insert before this CDPATH entry'
complete -c cdpath_add -n 'not __fish_prev_arg_in -a --after -b --before' -a '(__fish_complete_directories)'
