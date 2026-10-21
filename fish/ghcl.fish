function parse_ghurl --argument-names url
    # Remove the GitHub URL prefix, surrounding slashes, and query/fragment.
    set -l repo_path "$(string replace -r '^(https?://|git://|ssh://git@|git@)?github\.com[:/]' '' -- "$url")"
    set repo_path "$(string trim --chars / -- "$repo_path")"
    set repo_path "$(string replace -r '[?#].*$' '' -- "$repo_path")"

    set -l parts $(string split / -- "$repo_path")
    set -l owner "$parts[1]"
    set -l repo "$(string replace -r '\.git$' '' -- "$parts[2]")"

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
    set -l ghurl_array $(parse_ghurl "$url")
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
    if test -z "$target"
        set target .
    end
    if not test -e "$target"
        printf 'gho: %s: No such file or directory\n' "$target" >&2
        return 1
    end

    set -l dir "$target"
    set -l kind tree
    if not test -d "$target"
        set dir "$(dirname -- "$target")"
        set kind blob
    end

    if test "$(git -C "$dir" rev-parse --is-inside-work-tree 2>/dev/null)" != true
        printf 'gho: %s: Not inside a git work tree\n' "$target" >&2
        return 1
    end

    # Path relative to the repo root.
    set -l path "$(git -C "$dir" rev-parse --show-prefix)"
    if test "$kind" = blob
        set path "$path$(basename -- "$target")"
    end
    set path "$(string trim --right --chars / -- "$path")"

    # Prefer the branch's upstream: its remote and its name on that remote.
    set -l remote origin
    set -l ref
    set -l branch "$(git -C "$dir" symbolic-ref -q --short HEAD)"
    if test -n "$branch"
        set -l upstream "$(git -C "$dir" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)"
        set -l upstream_remote "$(git -C "$dir" config "branch.$branch.remote")"
        if test -n "$upstream" -a -n "$upstream_remote" -a "$upstream_remote" != .
            set remote "$upstream_remote"
            set ref "$(string replace -- "$remote/" '' "$upstream")"
        else if git -C "$dir" show-ref -q --verify "refs/remotes/origin/$branch"
            set ref "$branch"
        end
    end
    if test -z "$ref"
        set ref "$(git -C "$dir" describe --tags --exact-match HEAD 2>/dev/null)"
    end
    if test -z "$ref"
        set ref "$(git -C "$dir" rev-parse HEAD)"; or return
    end

    set -l remote_url "$(git -C "$dir" remote get-url "$remote")"; or return
    set -l repo "$(string match -rg '^(?:https?://|ssh://)?(?:[^@/]+@)?github\.com[:/]+([^/]+/[^/]+?)(?:\.git)?/?$' -- "$remote_url")"
    if test -z "$repo"
        printf 'gho: %s: Not a GitHub remote: %s\n' "$remote" "$remote_url" >&2
        return 1
    end

    set -l url "https://github.com/$repo"
    if test -n "$path" -o "$ref" != "$(git -C "$dir" rev-parse --abbrev-ref "$remote/HEAD" 2>/dev/null | string replace -- "$remote/" '')"
        set url "$url/$kind/$(string escape --style=url -- "$ref")"
        if test -n "$path"
            set url "$url/$(string escape --style=url -- "$path")"
        end
    end
    echo "$url"
    open "$url"
end
