function sshv --description 'Open a remote path with netrw' --argument-names server path
    if contains -- "$argv" -h --help
        printf 'Usage: sshv SERVER [PATH]\nCheck the remote path with SSH, then open it in Neovim using netrw.\n'
        return 0
    end
    if test -z "$server"; or set -q argv[3]
        printf 'Usage: %s <server> [path]\n' "$(status current-function)" >&2
        return 1
    end
    set -l quoted_path "'$(string replace -a "'" "'\\''" -- "$path")'"
    set -l probe 'case "$1" in
    "~"|"~/"*) set -- "$HOME${1#\~}" ;;
esac
ls -Ld -- "${1:-.}" >/dev/null || exit
if test -d "${1:-.}"; then printf /; fi'
    set -l directory "$(ssh -- "$server" "sh -c '$probe' sh $quoted_path")"; or return
    set -l target "scp://$server/$path"
    if test "$directory" = /; and not string match -q '*/' -- "$target"
        set target "$target/"
    end
    nvim -- "$target"
end
