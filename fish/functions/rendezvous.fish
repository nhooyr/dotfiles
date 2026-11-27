function rendezvous
    set -g fish_bind_mode insert
    test -s "$RENDEZVOUS_FISH"; or return 1
    set -l request "$(cat "$RENDEZVOUS_FISH")"
    rm -- "$RENDEZVOUS_FISH"
    switch "$request"
        case exec
            commandline -f execute
        case path-widget recent-widget
            _fzf "fzf-$request"
    end
    return 0
end
