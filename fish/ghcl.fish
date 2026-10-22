function parse_ghurl --argument-names url
    # Return three lines: owner, repository, and clone URL.
    if test (count $argv) -ne 1; or test -z "$url"; or string match -qr '[[:space:][:cntrl:]]' -- "$url"
        printf 'parse_ghurl: expected owner/repo or a GitHub URL\n' >&2
        return 1
    end

    set -l transport https
    set -l authority github.com
    set -l repo_path "$url"
    set -l browser_url false

    if string match -rqi '\A(https?|git|ssh)://' -- "$url"
        set -l parts (string match -ri --groups-only '\A(https?|git|ssh)://([^/]+)/(.+)\z' -- "$url")
        if test (count $parts) -ne 3
            printf 'parse_ghurl: URL must include an owner and repository\n' >&2
            return 1
        end
        set transport (string lower -- "$parts[1]")
        set authority (string lower -- "$parts[2]")
        set repo_path "$parts[3]"
        if contains -- "$transport" http https
            set browser_url true
        end
    else if string match -rqi '\Agit@' -- "$url"
        set -l parts (string match -ri --groups-only '\Agit@([^:]+):(.+)\z' -- "$url")
        if test (count $parts) -ne 2
            printf 'parse_ghurl: expected git@github.com:owner/repo.git\n' >&2
            return 1
        end
        set transport ssh
        set authority (string lower -- "$parts[1]")
        set repo_path "$parts[2]"
    else if string match -rqi '\Agithub\.com(:[0-9]+)?/' -- "$url"
        set -l parts (string split -m 1 / -- "$url")
        set authority (string lower -- "$parts[1]")
        set repo_path "$parts[2]"
        set browser_url true
    end

    # A colon here separates the host from a port, never from the owner.
    if test "$transport" = ssh
        set authority (string replace -r '\Agit@' '' -- "$authority")
    end
    set -l address (string split -m 1 : -- "$authority")
    set -l host "$address[1]"
    set -l port "$address[2]"
    if not contains -- "$host" github.com ssh.github.com
        printf 'parse_ghurl: unsupported host\n' >&2
        return 1
    end
    if test "$host" = ssh.github.com; and test "$transport" != ssh
        printf 'parse_ghurl: unsupported host or SSH user\n' >&2
        return 1
    end
    if test (count $address) -eq 2
        set port (string replace -r '\A0+' '' -- "$port")
        if not string match -qr '\A[0-9]{1,5}\z' -- "$port"; or test "$port" -gt 65535
            printf 'parse_ghurl: port must be between 1 and 65535\n' >&2
            return 1
        end
    end

    # Browser links may point at a file, branch, issue, or settings page.
    if test "$browser_url" = true
        set repo_path (string replace -r '[?#].*\z' '' -- "$repo_path")
    end
    set repo_path (string trim -r -c / -- "$repo_path")
    if string match -rqi '(^|/)(\.|%2e){1,2}(/|$)' -- "$repo_path"
        printf 'parse_ghurl: URL paths cannot contain dot segments\n' >&2
        return 1
    end
    set -l parts (string split / -- "$repo_path")
    if test (count $parts) -lt 2
        printf 'parse_ghurl: expected an owner and repository\n' >&2
        return 1
    end
    if test "$browser_url" = false; and test (count $parts) -ne 2
        printf 'parse_ghurl: use a browser URL to clone from a subpage\n' >&2
        return 1
    end

    # Reject encoded controls before decoding: Fish truncates strings at NUL.
    if string match -rqi '%(0[0-9a-f]|1[0-9a-f]|7f)' -- "$parts[1]" "$parts[2]"
        printf 'parse_ghurl: repository names cannot contain control characters\n' >&2
        return 1
    end
    set -l owner (string unescape --style=url -- "$parts[1]")
    set -l repo (string unescape --style=url -- "$parts[2]")
    set repo (string replace -r '\.git\z' '' -- "$repo")
    # Enterprise-managed GitHub usernames can include an underscore.
    if not string match -qr '\A[A-Za-z0-9][A-Za-z0-9_-]*\z' -- "$owner"
        printf 'parse_ghurl: invalid owner name\n' >&2
        return 1
    end
    if not string match -qr '\A[A-Za-z0-9._-]+\z' -- "$repo"; or contains -- "$repo" . ..
        printf 'parse_ghurl: invalid repository name\n' >&2
        return 1
    end

    set -l remote "https://github.com/$owner/$repo.git"
    switch "$transport"
        case ssh
            if test -n "$port"
                set remote "ssh://git@$host:$port/$owner/$repo.git"
            else
                set remote "git@$host:$owner/$repo.git"
            end
        case http https
            if test -n "$port"
                set remote "$transport://$host:$port/$owner/$repo.git"
            end
        case git
            if test -n "$port"; and test "$port" != 9418
                printf 'parse_ghurl: custom git:// ports are not supported\n' >&2
                return 1
            end
    end
    printf '%s\n' "$owner" "$repo" "$remote"
end

function ghcl --argument-names url
    if test (count $argv) -ne 1; or test -z "$url"
        printf 'Usage: ghcl <owner/repo | github-url>\n' >&2
        return 1
    end
    set -l github (parse_ghurl "$url"); or return
    __ghcl_checkout "$github[3]" "$HOME/code/$github[1]/$github[2]"
end

function __ghcl_checkout --argument-names remote destination
    # Reuse a valid checkout, or let Git create one, then enter it.
    # Worktrees and submodules have a .git file rather than a directory.
    if test -e "$destination/.git"
        set -l root "$(git -C "$destination" rev-parse --show-toplevel 2>/dev/null)"; or begin
            printf 'ghcl: destination is not a valid Git checkout: %s\n' "$destination" >&2
            return 1
        end
        if test "$root" != "$(path resolve -- "$destination")"
            printf 'ghcl: destination is not a valid Git checkout: %s\n' "$destination" >&2
            return 1
        end
    else
        set -l parent (path dirname -Z -- "$destination" | string split0)
        mkdir -p -- "$parent"; or return
        # Git refuses nonempty destinations and cleans up a failed new clone.
        git clone -- "$remote" "$destination"; or return
    end
    cd -- "$destination"
end

function gho --argument-names target
    # Open a committed path on GitHub without fetching or changing Git refs.
    if test (count $argv) -gt 1
        printf 'Usage: gho [path]\n' >&2
        return 1
    end
    test -n "$target"; or set target .
    if not test -e "$target"; and not test -L "$target"
        printf 'gho: no such file or directory: %s\n' "$target" >&2
        return 1
    end

    set -l dir "$target"
    set -l kind tree
    if test -L "$target"; or not test -d "$target"
        set dir (path dirname -Z -- "$target" | string split0)
        set kind blob
    end
    set -l repo_path "$(git -C "$dir" rev-parse --show-prefix)"; or return
    if test "$kind" = blob
        set -l name (path basename -Z -- "$target" | string split0)
        set repo_path "$repo_path$name"
    end
    set -l commit "$(git -C "$dir" rev-parse --verify 'HEAD^{commit}' 2>/dev/null)"; or begin
        printf 'gho: repository has no commits\n' >&2
        return 1
    end
    if test -n "$repo_path"
        # Git's directory prefix ends with a slash; object names do not.
        if test "$kind" = tree
            set repo_path (string split -r -m 1 / -- "$repo_path")[1]
        end
        set -l object_type "$(git -C "$dir" cat-file -t "HEAD:$repo_path" 2>/dev/null)"; or begin
            printf 'gho: path is not in the current commit: %s\n' "$target" >&2
            return 1
        end
        # The local file type may have changed since the last commit.
        switch "$object_type"
            case tree commit
                set kind tree
            case blob
                set kind blob
        end
    end

    # Prefer the tracking remote and branch; otherwise use a commit permalink.
    set -l remote
    set -l ref "$commit"
    set -l branch "$(git -C "$dir" symbolic-ref -q HEAD)"
    if test -n "$branch"
        set -l upstream (git -C "$dir" for-each-ref \
            --format='%(upstream:remotename)%0a%(upstream:remoteref)' -- "$branch")
        if test -n "$upstream[1]"; and test "$upstream[1]" != .
            set remote "$upstream[1]"
            set ref (string replace -r '\Arefs/heads/' '' -- "$upstream[2]")
        end
    end
    if test -z "$remote"
        set -l remotes (git -C "$dir" remote)
        if contains -- origin $remotes
            set remote origin
        else if test (count $remotes) -eq 1
            set remote "$remotes[1]"
        else
            printf 'gho: set a tracking remote or add an origin remote\n' >&2
            return 1
        end
    end
    set -l remote_url "$(git -C "$dir" remote get-url "$remote")"; or return
    set -l github (parse_ghurl "$remote_url"); or return
    set -l url "https://github.com/$github[1]/$github[2]"

    # A cached default branch is enough; an unknown default needs no lookup.
    set -l default "$(git -C "$dir" symbolic-ref -q "refs/remotes/$remote/HEAD")"
    if test -n "$repo_path"; or test "$default" != "refs/remotes/$remote/$ref"
        set -l encoded_path (string escape --style=url -- "$ref/$repo_path")
        set url "$url/$kind/$(string trim -r -c / -- "$encoded_path")"
    end
    printf '%s\n' "$url"
    open "$url"
end
