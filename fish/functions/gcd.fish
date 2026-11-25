function gcd
    if contains -- "$argv" -h --help
        printf '%s\n' 'Usage: gcd
Change to the current Git working-tree root.'
        return
    end
    set -l git_root "$(git rev-parse --show-toplevel)"; or return 1
    cd -- "$git_root"
end
