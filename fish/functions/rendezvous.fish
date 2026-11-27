function rendezvous
    set -l request "$(test -s "$RENDEZVOUS_FISH"; and cat "$RENDEZVOUS_FISH")"
    switch "$request"
        case exec
            commandline -f execute; or return 1
        case path-widget recent-widget
            _fzf "fzf-$request"; or return 1
        case '*'
            return 1
    end
    set -g fish_bind_mode insert
    return 0
end
