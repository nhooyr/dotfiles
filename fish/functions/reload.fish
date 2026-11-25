function reload
    if contains -- "$argv" -h --help
        printf 'Usage: reload\nReload Fish configuration and merge history outside private mode.\n'
        return 0
    end
    for path in $compgen_paths
        complete -e -p "$path"
    end
    set -eg compgen_paths; or true
    source "$__fish_config_dir/config.fish"; or return
    if not set -q fish_private_mode
        history merge
    end
end
