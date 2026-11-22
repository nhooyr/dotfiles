function ghc --description 'Create a private GitHub repository and open its checkout'
    set -l usage 'Usage: ghc <OWNER/REPO>

Create a private GitHub repository, then open its checkout with ghe.
If the repository already exists, open its checkout instead.
Accepts exactly one OWNER/REPO argument; repository URLs and extra flags are not accepted.
Uses GH_HOST when set, otherwise github.com.

  -h, --help    Show this help.'
    0="$(status current-function)" usage="$usage" __ghc $argv
end

function __ghc --argument-names repository
    if test "$(count $argv)" -eq 1; and contains -- "$repository" -h --help
        printf '%s\n' "$usage"
        return 0
    end
    if test "$(count $argv)" -ne 1
        or not string match -qr '\A[A-Za-z0-9][A-Za-z0-9_-]*/(?!\.{1,2}\z)[A-Za-z0-9._-]+\z' -- "$repository"
        printf 'Usage: %s <OWNER/REPO>\n' "$0" >&2
        return 1
    end
    set -l error_file "$(mktemp)"; or return
    set -l url "$(gh repo create --private "$repository" 2>"$error_file")"
    set -l create_status "$status"
    set -l error_message "$(cat "$error_file")"
    rm -- "$error_file"
    if test "$create_status" -ne 0
        if not string match -q '*Name already exists on this account (createRepository)*' -- "$error_message"
            printf '%s\n' "$error_message" >&2
            return "$create_status"
        end
        set -l host "$GH_HOST"
        test -n "$host"; or set host github.com
        set url "https://$host/$repository"
    else if test -n "$error_message"
        printf '%s\n' "$error_message" >&2
    end
    printf '%s\n' "$url"
    ghe "$url"
end
