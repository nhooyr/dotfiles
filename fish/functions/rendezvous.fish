function rendezvous
    if set -q argv[1]
        rendezvous_init; or return
        "$argv[1]" $argv[2..]; or return
    end
    set -l request "$(test -s "$RENDEZVOUS_FISH"; and cat "$RENDEZVOUS_FISH")"
    switch "$request"
        case exec
            commandline -f execute; or return 1
        case path-widget recent-widget
            _fzf "fzf-$request"; or return 1
        case ''
            set -q argv[1]; or return 1
        case '*'
            return 1
    end
    set -g fish_bind_mode insert
    return 0
end
