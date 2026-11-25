function reload
    if contains -- "$argv" -h --help
        printf 'Usage: reload\nReload Fish configuration and merge history outside private mode.\n'
        return 0
    end
    set -l generated
    set -l paths
    for rule in $(complete --color never | string match '*compgen.pl*')
        printf '%s\n' "$rule" | read --local --tokenize --array fields
        test "$fields[2]" = -p; and test "$fields[4]" = -a; or continue
        string match -q -- '$(command perl *' "$fields[5]"; or continue
        set -a generated "$rule"
        contains -- "$fields[3]" $paths; or set -a paths "$fields[3]"
    end
    for path in $paths
        set -l saved
        for rule in $(complete --color never -c "$path")
            contains -- "$rule" $generated; or set -a saved "$rule"
        end
        complete -e -p "$path"
        # Fish lists newest rules first; restore them in the opposite order.
        for rule in $saved[-1..1]
            eval "$rule"
        end
    end
    set -eg compgen_paths; or true
    source "$__fish_config_dir/config.fish"; or return
    if not set -q fish_private_mode
        history merge
    end
end
