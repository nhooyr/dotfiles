complete -c gho -f
complete -c gho -s h -l help -d 'Show help'
complete -c gho -l copy -d 'Copy the URL without opening it'
complete -c gho -n '__gh_complete_target copy' -F -a '$(__gho_complete_targets)'

function __gho_complete_targets
    __gh_complete_repositories
    command git for-each-ref --format='%(refname:short)%09Git reference' refs/heads refs/remotes refs/tags 2>/dev/null
    and printf 'HEAD\tCurrent commit\n'
    set -l files $(command git ls-files -z 2>/dev/null | string split0 | string replace -r '^-' './-')
    set -q files[1]; and printf '%s\tTracked path\n' $files
end
