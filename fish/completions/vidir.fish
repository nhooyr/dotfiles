complete -c vidir -f
complete -c vidir -s h -l help -d 'Show help'
complete -c vidir -s r -l recursive -d 'Include descendants after parent directories'
complete -c vidir -l no-ignore -d 'Include Git-ignored entries and .git'
complete -c vidir -n '__fish_is_nth_token 1' -a '(__fish_complete_directories)'
