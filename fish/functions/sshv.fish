function sshv --description 'Open a remote path with netrw' --argument-names server path
    if test -z "$server"; or set -q argv[3]
        printf 'Usage: %s <server> [path]\n' "$(status current-function)" >&2
        return 1
    end
    set -l quoted_path "'$(string replace -a "'" "'\\''" -- "$path")'"
    set -l directory "$(ssh -- "$server" "sh -c 'if test -d \"\${1:-.}\"; then printf /; fi' sh $quoted_path")"; or return
    set -l target "scp://$server/$path"
    if test "$directory" = /; and not string match -q '*/' -- "$target"
        set target "$target/"
    end
    nvim -- "$target"
end
