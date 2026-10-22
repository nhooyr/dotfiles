function parse_ghurl --argument-names url
    # Remove the GitHub URL prefix, surrounding slashes, and query/fragment.
    set -l repo_path "$(string replace -r '^(https?://|git://|ssh://git@|git@)?github\.com[:/]' '' -- "$url")"
    set repo_path "$(string trim --chars / -- "$repo_path")"
    set repo_path "$(string replace -r '[?#].*$' '' -- "$repo_path")"

    set -l parts $(string split / -- "$repo_path")
    set -l owner "$parts[1]"
    set -l repo "$(string replace -r '\.git$' '' -- "$parts[2]")"
    if not string match -qr '^[A-Za-z0-9-]+$' -- "$owner"; or not string match -qr '^[A-Za-z0-9._-]+$' -- "$repo"
        printf 'parse_ghurl: %s: Not a GitHub repo\n' "$url" >&2
        return 1
    end

    set -l remote "https://github.com/$owner/$repo.git"
    if string match -qr '^(git@|ssh://)' -- "$url"
        set remote "git@github.com:$owner/$repo.git"
    end

    echo "$owner"
    echo "$repo"
    echo "$remote"
end
function ghcl --argument-names url
    if test -z "$url"
        printf 'Usage: ghcl <owner/repo | github-url>\n' >&2
        return 1
    end
    set -l ghurl_array $(parse_ghurl "$url"); or return 1
    set -l owner "$ghurl_array[1]"
    set -l repo "$ghurl_array[2]"
    set -l remote "$ghurl_array[3]"

    set -l repo_dir "$HOME/code/$owner/$repo"
    if not test -d "$repo_dir/.git"
        git ls-remote "$remote" >/dev/null; or return 1
        mkdir -p "$repo_dir"
        git clone -- "$remote" "$repo_dir"; or return 1
    end
    cd "$repo_dir"
end
function gho --argument-names target
    # Open the GitHub page for a path in the current repo, at the checked-out
    # branch, tag or commit. Defaults to the current directory.
    test -n "$target"; or set target .
    if not test -e "$target"
        printf 'gho: %s: No such file or directory\n' "$target" >&2
        return 1
    end

    set -l dir "$target"
    set -l kind tree
    if not test -d "$target"
        set dir "$(path dirname -- "$target")"
        set kind blob
    end

    # Path relative to the repo root.
    set -l path "$(git -C "$dir" rev-parse --show-prefix)"; or return
    if test "$kind" = blob
        set path "$path$(path basename -- "$target")"
    end

    # Prefer the branch's upstream, then an exact tag, then the commit.
    set -l remote origin
    set -l ref
    set -l upstream $(git -C "$dir" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null | string split -m1 /)
    if set -q upstream[2]
        set remote "$upstream[1]"
        set ref "$upstream[2]"
    else
        set ref "$(git -C "$dir" describe --tags --exact-match 2>/dev/null; or git -C "$dir" rev-parse HEAD)"
    end

    set -l ghurl $(parse_ghurl "$(git -C "$dir" remote get-url "$remote")"); or return
    set -l url "https://github.com/$ghurl[1]/$ghurl[2]"

    # At the root on the default branch, the plain repo page is enough.
    set -l default "$(git -C "$dir" rev-parse --abbrev-ref "$remote/HEAD" 2>/dev/null)"
    if test -n "$path" -o "$remote/$ref" != "$default"
        set url "$url/$kind/$(string escape --style=url -- "$ref/$path" | string trim -r -c /)"
    end
    echo "$url"
    open "$url"
end
