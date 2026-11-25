complete -c ghc -f
complete -c ghc -n 'test "$(count $(commandline -xpc))" -eq 1' -s h -l help -d 'Show help'
complete -c ghc -n __gh_complete_target -a '$(__gh_complete_repositories)'
