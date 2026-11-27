function rendezvous
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
    end
    if test "$fish_bind_mode" != insert
        set -g fish_bind_mode insert
    end
    return 0
end
