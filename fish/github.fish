function ghg --description 'Upload files or clipboard text as a GitHub gist'
    set -l usage 'Usage: ghg [-p|--public] [FILE...]

Create a secret gist from FILEs, or from the clipboard when no files are given.
Use - as a filename to read from standard input instead of the clipboard.
Print the gist URL and copy it to the clipboard with pbc.

  -p, --public    Create a public gist.
  -h, --help      Show this help.

Examples:
  ghg                    Upload the clipboard as a secret gist.
  ghg -p                 Upload the clipboard as a public gist.
  ghg file.txt other.md   Upload multiple files.
  printf hello | ghg -   Upload standard input.'
    argparse --name "$(status current-function)" h/help p/public -- $argv; or return
    if set -q _flag_help
        printf '%s\n' "$usage"
        return 0
    end
    set -l flags
    set -q _flag_public; and set flags --public
    set -l url
    if set -q argv[1]
        set url "$(gh gist create $flags -- $argv)"; or return
    else
        set url "$(pbpaste | gh gist create $flags -- -)"; or return
    end
    printf '%s\n' "$url" | pbc
end

# Shared URL parsing for ghe and gho.
function __gh_parse --argument-names input
    # Return owner/repo, the URL's remaining path, a clone URL, and its API host.
    # Reject controls before decoding can strip trailing newlines.
    if string match -rqi '%[01][0-9a-f]|%7f|[[:cntrl:]]' -- "$input"
        printf '%s: invalid input\n' "$0" >&2
        return 1
    end
    # Accept GitHub's standard endpoints and the configured GitHub host.
    set -l host "$GH_HOST"
    test -n "$host"; or set host github.com
    set host "$(string lower -- "$host")"
    set -l configured_authority "$host"
    set host "$(string replace -r ':443$' '' -- "$host")"
    set -l configured_host "$host"
    set -l https_authority 'github\.com(?::443)?|raw\.githubusercontent\.com(?::443)?'
    set -l http_authority 'github\.com(?::80)?|raw\.githubusercontent\.com(?::80)?'
    set -l ssh_authority 'github\.com(?::22)?|ssh\.github\.com:443'
    set -l scp_host 'github\.com'
    set -l bare_authority 'github\.com(?::443)?'
    if test "$configured_authority" != "$host"
        set http_authority "$http_authority|$(string escape --style=regex -- "$configured_authority")"
    end
    if test "$host" != github.com
        set -l configured $(string escape --style=regex -- "$host")
        set -l ssh_name $(string escape --style=regex -- $(string replace -r ':[0-9]+$' '' -- "$host"))
        if string match -qr ':[0-9]+$' -- "$host"
            set https_authority "$https_authority|$configured"
            set http_authority "$http_authority|$configured"
            set bare_authority "$bare_authority|$configured"
        else
            set https_authority "$https_authority|$configured(?::443)?"
            set http_authority "$http_authority|$configured(?::80)?"
            set bare_authority "$bare_authority|$configured(?::443)?"
        end
        set ssh_authority "$ssh_authority|$ssh_name(?::[0-9]+)?"
        set scp_host "$scp_host|$ssh_name"
    end
    set -l http_userinfo '(?:[A-Za-z0-9._~!$&\'()*+,;=:-]|%[0-9a-f]{2})+'
    set -l is_url true
    set -l path $(string replace -ri "^(https://(?:$http_userinfo@)?(?:$https_authority)/|http://(?:$http_userinfo@)?(?:$http_authority)/|ssh://git@(?:$ssh_authority)/|git@(?:$scp_host):|(?:$bare_authority)/(?=[^/]+/[^/]+))" '' -- "$input"); or set is_url false
    if set -l authority $(string match -rgi "^https?://(?:$http_userinfo@)?([^/]+)/" -- "$input")
        set host "$(string lower -- "$authority")"
        if string match -rqi '^http://' -- "$input"; and test "$host" != "$configured_host"
            set host "$(string replace -r ':80$' '' -- "$host")"
        end
        set host "$(string replace -r ':443$' '' -- "$host")"
    else if set -l authority $(string match -rgi '^(?:ssh://git@|git@)([^/:]+)' -- "$input")
        set host "$(string lower -- "$authority")"
        if test "$host" = "$(string replace -r ':[0-9]+$' '' -- "$configured_host")"
            set host "$configured_host"
        end
    else if test "$is_url" = true
        set host "$(string lower -- "$(string split -m 1 -f 1 / -- "$input")")"
        set host "$(string replace -r ':443$' '' -- "$host")"
    end
    if contains -- "$host" raw.githubusercontent.com ssh.github.com
        set host github.com
    end
    if string match -qr '[[:cntrl:]]' -- "$host"
        printf '%s: invalid GitHub hostname\n' "$0" >&2
        return 1
    end
    set path $(string replace -r '[?#].*$' '' -- "$path")
    set path "$(string trim -r -c / -- "$path")"
    set -l parts $(string split -m 2 / -- "$path")
    set -l repo $(string replace -r '\.git$' '' -- "$parts[2]")
    if not string match -qr '^[A-Za-z0-9][A-Za-z0-9_-]*$' -- "$parts[1]"
        printf '%s: expected owner/repo or a GitHub URL\n' "$0" >&2
        return 1
    end
    if not string match -qr '^[A-Za-z0-9._-]+$' -- "$repo"; or contains -- "$repo" . ..
        printf '%s: invalid repository name\n' "$0" >&2
        return 1
    end
    if test "$is_url" = false; and test "$(count $parts)" -gt 2
        printf '%s: use a GitHub URL to specify a ref or file\n' "$0" >&2
        return 1
    end
    # Browsers can display and copy IRIs, but URL unescaping accepts only ASCII.
    for text in $(string match -ar '[^\x00-\x7f]+' -- "$parts[3]")
        set parts[3] $(string replace -- "$text" $(string escape --style=url -- "$text") "$parts[3]")
    end
    set -l tail "$(string unescape --style=url -- "$parts[3]")"; or begin
        printf '%s: invalid URL encoding\n' "$0" >&2
        return 1
    end
    if string match -qr '(^|/)\.{1,2}(/|$)' -- "$tail"
        printf '%s: URL paths cannot contain dot segments\n' "$0" >&2
        return 1
    end
    if string match -rqi "^https?://(?:$http_userinfo@)?raw\\.githubusercontent\\.com(?::[0-9]+)?/" -- "$input"
        set tail "raw/$tail"
    end
    set -l userinfo $(string match -rgi "^https?://($http_userinfo@)[^/]+/" -- "$input")
    set -l remote "https://$userinfo[1]$host/$parts[1]/$repo.git"
    set -l ssh_prefix $(string match -ri '^ssh://git@[^/]+:[0-9]+/' -- "$input")
    if test -n "$ssh_prefix"
        set remote "$(string lower -- "$ssh_prefix")$parts[1]/$repo.git"
    else if string match -rqi '^(git@|ssh://git@)' -- "$input"
        set remote "git@$(string replace -r ':[0-9]+$' '' -- "$host"):$parts[1]/$repo.git"
    end
    printf '%s\n' "$parts[1]/$repo" "$tail" "$remote" "$host"
end
