function __gh_parse --argument-names input
    # Return three lines: owner/repo, the URL's remaining path, and a clone URL.
    if string match -rqi '%00|[[:cntrl:]]' -- "$input"
        printf '%s: invalid input\n' "$0" >&2
        return 1
    end
    set -l path (string replace -ri '^(https?://github\.com/|ssh://git@github\.com/|git@github\.com:|github\.com/)' '' -- "$input")
    set -l is_url false
    test "$path" != "$input"; and set is_url true
    set path (string replace -r '[?#].*$' '' -- "$path")
    set path (string trim -r -c / -- "$path")
    set -l parts (string split -m 2 / -- "$path")
    set -l repo (string replace -r '\.git$' '' -- "$parts[2]")
    if not string match -qr '^[A-Za-z0-9][A-Za-z0-9_-]*$' -- "$parts[1]"
        printf '%s: expected owner/repo or a GitHub URL\n' "$0" >&2
        return 1
    end
    if not string match -qr '^[A-Za-z0-9._-]+$' -- "$repo"; or contains -- "$repo" . ..
        printf '%s: invalid repository name\n' "$0" >&2
        return 1
    end
    if test "$is_url" = false; and test (count $parts) -gt 2
        printf '%s: use a GitHub URL to specify a ref or file\n' "$0" >&2
        return 1
    end
    set -l tail "$(string unescape --style=url -- "$parts[3]")"; or return
    if string match -qr '(^|/)\.{1,2}(/|$)' -- "$tail"
        printf '%s: URL paths cannot contain dot segments\n' "$0" >&2
        return 1
    end
    set -l remote "https://github.com/$parts[1]/$repo.git"
    if string match -rqi '^(git@|ssh://git@)' -- "$input"
        set remote "git@github.com:$parts[1]/$repo.git"
    end
    printf '%s\n' "$parts[1]/$repo" "$tail" "$remote"
end

function __gh_resolve --argument-names remote tail
    # A ref can contain slashes. Try the longest advertised name first.
    set -l route (string split -m 1 / -- "$tail")
    if not contains -- "$route[1]" blob tree commit; or test -z "$route[2]"
        printf '%s: expected a repository, blob, tree, or commit URL\n' "$0" >&2
        return 1
    end
    set -l advertised (git ls-remote --refs --heads --tags -- "$remote"); or return
    set -l refs
    for line in $advertised
        set -a refs (string split -f 2 \t -- "$line")
    end

    set -l ref "$route[2]"
    set -l path ''
    while true
        set -l full_ref
        if contains -- "refs/tags/$ref" $refs
            set full_ref "refs/tags/$ref"
        else if contains -- "refs/heads/$ref" $refs
            set full_ref "refs/heads/$ref"
        else if string match -qr '^[0-9a-fA-F]{4,40}$' -- "$ref"
            set full_ref "$ref"
        end
        if test -n "$full_ref"
            printf '%s\n' "$full_ref" "$ref" (string trim -r -c / -- "$path")
            return 0
        end
        set -l parts (string split -r -m 1 / -- "$ref")
        if test (count $parts) -ne 2
            printf '%s: no branch, tag, or commit matches this URL\n' "$0" >&2
            return 1
        end
        set ref "$parts[1]"
        set path "$parts[2]/$path"
    end
end

function __ghe_checkout --argument-names remote destination tail
    if test -e "$destination/.git"
        set -l root "$(git -C "$destination" rev-parse --show-toplevel)"; or return
        if test "$root" != "$(path resolve -- "$destination")"
            printf '%s: destination is not a repository root: %s\n' "$0" "$destination" >&2
            return 1
        end
    else
        mkdir -p -- "$(path dirname -- "$destination")"; or return
        git clone -- "$remote" "$destination"; or return
    end

    set -l target "$destination"
    if test -n "$tail"
        set -l resolved (__gh_resolve "$remote" "$tail")
        test (count $resolved) -eq 3; or return 1
        set -l full_ref "$resolved[1]"
        set -l ref "$resolved[2]"
        set -l changes "$(git -C "$destination" status --porcelain --untracked-files=all)"; or return
        if test -n "$changes"
            printf '%s: keeping the current ref because the checkout has local changes\n' "$0" >&2
        else
            set -l revision
            if not string match -q 'refs/*' -- "$full_ref"
                # Git can resolve a local abbreviated SHA; servers require the full SHA.
                set revision "$(git -C "$destination" rev-parse --verify "$full_ref^{commit}" 2>/dev/null)"
            end
            if test -z "$revision"
                git -C "$destination" fetch --quiet --no-recurse-submodules -- "$remote" "$full_ref"; or return
                set revision FETCH_HEAD
            end
            if string match -q 'refs/heads/*' -- "$full_ref"
                if git -C "$destination" show-ref --verify --quiet "refs/heads/$ref"
                    git -C "$destination" switch --quiet --no-overwrite-ignore -- "$ref"; or return
                else
                    git -C "$destination" switch --quiet --no-overwrite-ignore --no-track --create "$ref" "$revision"; or return
                end
            else
                git -C "$destination" switch --quiet --no-overwrite-ignore --detach "$revision"; or return
            end
        end

        if test -n "$resolved[3]"
            set target "$destination/$resolved[3]"
            if not test -e "$target"; and not test -L "$target"
                printf '%s: path does not exist in this checkout: %s\n' "$0" "$resolved[3]" >&2
                return 1
            end
        end
    end
    if test "$target" = "$destination"
        cd -- "$destination"
        return $status
    end
    if test -d "$target"; and not test -L "$target"
        cd -- "$target"
    else
        cd -- "$(path dirname -- "$target")"; or return
        if not set -q EDITOR[1]; or test -z "$EDITOR"
            printf '%s: EDITOR is not set\n' "$0" >&2
            return 1
        end
        # Respect quoted arguments in EDITOR without evaluating shell commands.
        printf '%s\n' "$EDITOR" | read --tokenize --array --local editor; or return
        if test (count $editor) -eq 0
            printf '%s: EDITOR is empty\n' "$0" >&2
            return 1
        end
        $editor "$target"
    end
end

function ghe --argument-names input
    # Fish doesn't set $0; export it locally so the helpers inherit this name.
    set -lx 0 (status current-function)
    if test (count $argv) -ne 1; or test -z "$input"
        printf 'Usage: %s <owner/repo | github-url>\n' "$0" >&2
        return 1
    end
    set -l github (__gh_parse "$input")
    test (count $github) -eq 3; or return 1
    __ghe_checkout "$github[3]" "$HOME/code/$github[1]" "$github[2]"
end

function gho --argument-names target
    set -lx 0 (status current-function)
    if test (count $argv) -gt 1
        printf 'Usage: %s [path | owner/repo | github-url]\n' "$0" >&2
        return 1
    end
    if test (count $argv) -eq 0
        set target "$PWD"
    end

    # Inspect the final entry itself, including a symlink followed by a slash.
    set -l parent "$(path dirname -- "$target")"
    set -l name "$(path basename -- "$target")"
    set -l entry "$parent/$name"
    if not test -e "$target"; and not test -L "$entry"
        set -l github (__gh_parse "$target")
        test (count $github) -eq 3; or return 1
        set -l url "https://github.com/$github[1]"
        if test -n "$github[2]"
            set url "$url/$(string escape --style=url -- "$github[2]")"
        end
        printf '%s\n' "$url"
        open "$url"
        return
    end

    set -l dir "$target"
    set -l is_file false
    if test -L "$entry"; or not test -d "$target"
        set dir "$parent"
        set is_file true
    end
    set -l repo_path "$(git -C "$dir" rev-parse --show-prefix 2>/dev/null)"; or begin
        # Installed dotfile links may live outside their source repository.
        if test -L "$entry"; and test -e "$entry"
            set -l resolved "$(path resolve -- "$entry")"; or return
            "$0" "$resolved"
            return $status
        end
        printf '%s: path is not in a Git checkout: %s\n' "$0" "$target" >&2
        return 1
    end
    if test "$is_file" = true
        set repo_path "$repo_path$name"
    else if test -n "$repo_path"
        # Git's directory prefix ends in /.
        set -l parts (string split -r -m 1 / -- "$repo_path")
        set repo_path "$parts[1]"
    end
    set -l commit "$(git -C "$dir" rev-parse --verify 'HEAD^{commit}' 2>/dev/null)"; or begin
        if test -n "$repo_path"
            printf '%s: repository has no commits\n' "$0" >&2
            return 1
        end
    end
    set -l kind tree
    if test -n "$repo_path"
        set kind "$(git -C "$dir" cat-file -t "HEAD:$repo_path" 2>/dev/null)"; or begin
            printf '%s: path is not in the current commit: %s\n' "$0" "$target" >&2
            return 1
        end
        if test "$kind" != tree; and test "$kind" != blob
            printf '%s: unsupported Git object at path: %s\n' "$0" "$target" >&2
            return 1
        end
    end

    # Only select a remote branch when its cached commit matches this checkout.
    set -l remote
    set -l ref
    set -l branch "$(git -C "$dir" symbolic-ref -q HEAD)"
    if test -n "$branch"
        set -l upstream (git -C "$dir" for-each-ref --format='%(upstream:remotename)%0a%(upstream:remoteref)%0a%(upstream)' -- "$branch")
        if test -n "$upstream[1]"; and test "$upstream[1]" != .
            set remote "$upstream[1]"
            if test -n "$upstream[3]"; and string match -q 'refs/heads/*' -- "$upstream[2]"
                set -l tracked "$(git -C "$dir" rev-parse --verify "$upstream[3]^{commit}" 2>/dev/null)"
                if test "$tracked" = "$commit"
                    set ref (string replace -r '\Arefs/heads/' '' -- "$upstream[2]")
                end
            end
        end
    end
    if test -z "$remote"
        set -l remotes (git -C "$dir" remote)
        if contains -- origin $remotes
            set remote origin
        else if test (count $remotes) -eq 1
            set remote "$remotes[1]"
        else
            printf '%s: set a tracking remote or add an origin remote\n' "$0" >&2
            return 1
        end
    end
    if test -z "$ref"; and test -n "$branch"
        set -l branch_name (string replace -r '\Arefs/heads/' '' -- "$branch")
        set -l tracked "$(git -C "$dir" rev-parse --verify "refs/remotes/$remote/$branch_name^{commit}" 2>/dev/null)"
        if test "$tracked" = "$commit"
            set ref "$branch_name"
        end
    end
    if test -z "$ref"; and test -z "$branch"
        set ref "$(git -C "$dir" describe --tags --exact-match HEAD 2>/dev/null)"
    end
    test -n "$ref"; or set ref "$commit"
    # A shared branch/tag name is ambiguous in a browser URL; use the commit.
    if git -C "$dir" show-ref --verify --quiet "refs/tags/$ref"; and git -C "$dir" show-ref --verify --quiet "refs/remotes/$remote/$ref"
        set ref "$commit"
    end

    set -l remote_url "$(git -C "$dir" remote get-url "$remote")"; or return
    set -l github (__gh_parse "$remote_url")
    test (count $github) -eq 3; or return 1
    set -l url "https://github.com/$github[1]"
    if test -n "$commit"
        set -l web_path "$ref"
        test -z "$repo_path"; or set web_path "$web_path/$repo_path"
        set url "$url/$kind/$(string escape --style=url -- "$web_path")"
    end
    printf '%s\n' "$url"
    open "$url"
end
