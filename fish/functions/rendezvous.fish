function rendezvous
    set -g fish_bind_mode insert
    set -l request "$(test -s "$RENDEZVOUS_FISH"; and cat "$RENDEZVOUS_FISH")"
    switch "$request"
        case exec
            commandline -f execute
        case path-widget recent-widget
            _fzf "fzf-$request"
        case *
            return 1
    end
    return 0
end
