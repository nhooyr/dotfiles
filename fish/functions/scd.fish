function scd
    set -l super_root "$(git rev-parse --show-superproject-working-tree)"; or return 1
    # Git prints nothing, and still succeeds, outside a submodule.
    if test -z "$super_root"
        printf '%s: not inside a submodule\n' "$(status function)" >&2
        return 1
    end
    cd -- "$super_root"
end
