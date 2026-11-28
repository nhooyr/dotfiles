function rendezvous
    set -l request "$(test -s "$RENDEZVOUS_FISH"; and cat "$RENDEZVOUS_FISH")"
    switch "$request"
        case ''
            test "$fish_bind_mode" != insert; and set -g fish_bind_mode insert
            return 0
        case exec
            test "$fish_bind_mode" != insert; and set -g fish_bind_mode insert
            commandline -f execute
        case path-widget recents-widget
            _fzf "fzf-$request"
        case '*'
            return 1
    end
end
