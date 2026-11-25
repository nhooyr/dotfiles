function gcd
    set -l git_root "$(git rev-parse --show-toplevel)"; or return 1
    cd -- "$git_root"
end
