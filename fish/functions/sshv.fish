function sshv --description 'Open a remote path with netrw' --argument-names server path
    if test -z "$server"; or set -q argv[3]
        printf 'Usage: %s <server> [path]\n' "$(status current-function)" >&2
        return 1
    end
    nvim -- "scp://$server/$path"
end
