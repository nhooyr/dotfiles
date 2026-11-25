function reload
    if contains -- "$argv" -h --help
        printf 'Usage: reload\nReload Fish configuration and merge history outside private mode.\n'
        return 0
    end
    source "$__fish_config_dir/config.fish"; or return
    if not set -q fish_private_mode
        history merge
    end
end
