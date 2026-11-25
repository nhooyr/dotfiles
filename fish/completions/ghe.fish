complete -c ghe -f
complete -c ghe -s h -l help -d 'Show help'
complete -c ghe -n __gh_complete_target -a '$(__gh_complete_repositories)'
