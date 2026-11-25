complete -c ghss -f
complete -c ghss -s h -l help -d 'Show help'
complete -c ghss -n __gh_complete_target -k -a '$(__fish_complete_suffix .png .jpg .jpeg)'
