function reload
    source "$__fish_config_dir/config.fish"; or return
    if not set -q fish_private_mode
        history merge
    end
end
