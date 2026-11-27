function rendezvous
    if set -q argv[1]
        rendezvous_init; or return
        # Let the editor restore an insertion position even while vi Normal mode is active.
        fish_cursor_end_mode=exclusive "$argv[1]" $argv[2..]; or return
    end
    if test -s "$RENDEZVOUS_FISH"
        set -l request "$(cat "$RENDEZVOUS_FISH")"
        switch "$request"
            case exec
                commandline -f execute
            case path-widget recent-widget
                _fzf "fzf-$request"; or return 1
            case '*'
                return 1
        end
    else if set -q argv[1]
        return 1
    end
    if test "$fish_bind_mode" != insert
        set -g fish_bind_mode insert
    end
    return 0
end
