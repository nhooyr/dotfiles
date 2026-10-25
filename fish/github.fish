function __gh_parse --argument-names input
    # Return three lines: owner/repo, the URL's remaining path, and a clone URL.
    # Reject controls before decoding can strip trailing newlines.
    if string match -rqi '%[01][0-9a-f]|%7f|[[:cntrl:]]' -- "$input"
        printf '%s: invalid input\n' "$0" >&2
        return 1
    end
    # Accept GitHub's standard ports and its alternate SSH endpoint.
    set -l path (string replace -ri '^(https://github\.com(:443)?/|http://github\.com(:80)?/|ssh://git@(github\.com(:22)?|ssh\.github\.com:443)/|git@github\.com:|github\.com(:443)?/)' '' -- "$input")
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
    set -l ssh_authority (string match -ri '^ssh://git@[^/]+:[0-9]+/' -- "$input")
    if test -n "$ssh_authority"
        set remote "$(string lower -- "$ssh_authority")$parts[1]/$repo.git"
    else if string match -rqi '^(git@|ssh://git@)' -- "$input"
        set remote "git@github.com:$parts[1]/$repo.git"
    end
    printf '%s\n' "$parts[1]/$repo" "$tail" "$remote"
end

function __gh_remotes --argument-names remote destination
    # Match GitHub repositories across HTTPS and SSH URLs.
    set -l requested (__gh_parse "$remote")
    test (count $requested) -eq 3; or return 1
    set -l remotes (git -C "$destination" remote); or return
    for name in $remotes
        set -l url "$(git -C "$destination" remote get-url -- "$name")"; or return
        set -l github (__gh_parse "$url" 2>/dev/null)
        if test (count $github) -eq 3; and test (string lower -- "$github[1]") = (string lower -- "$requested[1]")
            printf '%s\n' "$name"
        end
    end
end

function __gh_map_ref --argument-names source target ref
    set -l parts (string split -m 1 '*' -- "$source")
    if test (count $parts) -eq 1
        test "$source" = "$ref"; or return 1
        printf '%s\n' "$target"
    else
        set -l pattern "^$(string escape --style=regex -- "$parts[1]")(.*)$(string escape --style=regex -- "$parts[2]")\$"
        set -l matched (string match -r -- "$pattern" "$ref")
        test (count $matched) -eq 2; or return 1
        string replace -- '*' "$matched[2]" "$target"
    end
end

function __gh_tracking_ref --argument-names ref
    # Git applies exclusions before choosing the first matching fetch mapping.
    for spec in $argv[2..]
        if string match -q '^*' -- "$spec"
            set -l source (string sub -s 2 -- "$spec")
            if __gh_map_ref "$source" "$source" "$ref" >/dev/null
                return 2
            end
        end
    end
    for spec in $argv[2..]
        set -l fields (string split -m 1 : -- (string replace -r '^\+' '' -- "$spec"))
        if test (count $fields) -eq 2; and test -n "$fields[2]"
            set -l target (__gh_map_ref "$fields[1]" "$fields[2]" "$ref")
            if test -n "$target"
                printf '%s\n' "$target"
                return 0
            end
        end
    end
    return 1
end

function __gh_source_ref --argument-names ref
    set -l fallback
    for spec in $argv[2..]
        set -l fields (string split -m 1 : -- (string replace -r '^\+' '' -- "$spec"))
        if test (count $fields) -eq 2; and test -n "$fields[2]"
            set -l source (__gh_map_ref "$fields[2]" "$fields[1]" "$ref")
            if string match -q 'refs/heads/*' -- "$source"
                set -l target (__gh_tracking_ref "$source" $argv[2..]); or continue
                if test "$target" = "$ref"
                    printf '%s\n' "$source"
                    return 0
                end
                test -n "$fallback"; or set fallback "$source"
            end
        end
    end
    # A cached HEAD alias may still point at a secondary fetch destination.
    if test -n "$fallback"
        printf '%s\n' "$fallback"
        return 0
    end
    return 1
end

function __gh_cached_branches --argument-names name destination
    set -l refspecs (git -C "$destination" config --get-all "remote.$name.fetch")
    set -l prefixes
    for spec in $refspecs
        set -l fields (string split -m 1 : -- (string replace -r '^\+' '' -- "$spec"))
        if test (count $fields) -eq 2; and test -n "$fields[2]"
            set -l parts (string split -m 1 '*' -- "$fields[2]")
            set -l prefix "$parts[1]"
            if test (count $parts) -eq 2
                set prefix (string replace -r '[^/]*$' '' -- "$prefix")
            end
            contains -- "$prefix" $prefixes; or set -a prefixes "$prefix"
        end
    end
    test (count $prefixes) -gt 0; or return 0
    set -l refs (git -C "$destination" for-each-ref \
        --format='%(if)%(symref)%(then)%(else)%(refname)%(end)' $prefixes); or return
    for ref in $refs
        set -l source (__gh_source_ref "$ref" $refspecs); or continue
        set -l target (__gh_tracking_ref "$source" $refspecs); or continue
        if test "$ref" = "$target"
            set -l branch (string replace -r '^refs/heads/' '' -- "$source")
            printf '%s\t%s\n' "refs/remotes/$name/$branch" "$ref"
        end
    end
end

function __gh_resolve --argument-names remote tail destination cached_only
    # Return the full ref, short name, path, and a locally usable revision or OID.
    set -l route (string split -m 1 / -- "$tail")
    if not contains -- "$route[1]" blob tree commit; or test -z "$route[2]"
        printf '%s: expected a repository, blob, tree, or commit URL\n' "$0" >&2
        return 1
    end
    # Commit URLs must stay unambiguous even when a ref has the same name.
    set -l commit_path (string split -m 1 / -- "$route[2]")
    if string match -qr '^[0-9a-fA-F]{40}$' -- "$commit_path[1]"
        printf '%s\n' "$commit_path[1]" "$commit_path[1]" (string trim -r -c / -- "$commit_path[2]") "$commit_path[1]"
        return 0
    end
    # Prefer local refs, including cached branches from the requested repository.
    set -l prefixes refs/tags refs/heads
    # Symbolic aliases such as origin/HEAD aren't branch names to check out.
    set -l refs (git -C "$destination" for-each-ref \
        --format='%(if)%(symref)%(then)%(else)%(refname)%(end)' $prefixes); or return
    set -l revisions $refs
    set -l remotes (__gh_remotes "$remote" "$destination"); or return
    for name in $remotes
        set -a prefixes "refs/remotes/$name"
        set -l cached (__gh_cached_branches "$name" "$destination"); or return
        for line in $cached
            set -l fields (string split \t -- "$line")
            set -a refs "$fields[1]"
            set -a revisions "$fields[2]"
        end
    end

    for source in cached remote
        if test "$source" = remote
            # gho only needs to check ambiguity among locally known refs.
            test "$cached_only" != true; or return 1
            set -l advertised (git ls-remote --refs --heads --tags -- "$remote"); or return
            set refs
            set revisions
            for line in $advertised
                set -l fields (string split \t -- "$line")
                set -a refs "$fields[2]"
                set -a revisions "$fields[1]"
            end
            set prefixes refs/tags refs/heads
        end

        # Ref names can contain slashes. Try the longest known name first.
        set -l ref "$route[2]"
        set -l path ''
        while true
            for prefix in $prefixes
                set -l index (contains -i -- "$prefix/$ref" $refs)
                if test -n "$index"
                    printf '%s\n' "$prefix/$ref" "$ref" (string trim -r -c / -- "$path") "$revisions[$index]"
                    return 0
                end
            end
            if string match -qr '^[0-9a-fA-F]{4,39}$' -- "$ref"
                # A short hex name may be a branch, such as 2026/fix.
                if test "$source" = remote; or git --no-lazy-fetch -C "$destination" cat-file -e "$ref^{commit}" 2>/dev/null
                    printf '%s\n' "$ref" "$ref" (string trim -r -c / -- "$path") "$ref"
                    return 0
                end
            end
            set -l parts (string split -r -m 1 / -- "$ref")
            if test (count $parts) -ne 2
                break
            end
            set ref "$parts[1]"
            set path "$parts[2]/$path"
        end
    end
    printf '%s: no branch, tag, or commit matches this URL\n' "$0" >&2
    return 1
end

function __ghe_remote --argument-names remote destination ref full_ref
    set -l remotes (__gh_remotes "$remote" "$destination"); or return
    set -l name "$remotes[1]"
    # Keep using the remote whose cached branch was resolved.
    for candidate in $remotes
        if test "$full_ref" = "refs/remotes/$candidate/$ref"
            set name "$candidate"
            break
        end
    end
    if test -z "$name"
        printf '%s: no remote matches the requested repository\n' "$0" >&2
        return 1
    end
    printf '%s\n' "$name"
end

function __ghe_tracking_ref --argument-names name destination ref
    set -l branch_ref "refs/heads/$ref"
    set -l refspecs (git -C "$destination" config --get-all "remote.$name.fetch")
    set -l tracking_ref (__gh_tracking_ref "$branch_ref" $refspecs)
    set -l mapping_status "$status"
    if test "$mapping_status" -eq 2
        printf '%s: branch is excluded by the remote fetch configuration: %s/%s\n' "$0" "$name" "$ref" >&2
        return 1
    else if test -z "$tracking_ref"
        # Single-branch clones need a mapping for future fetches, too.
        set tracking_ref "refs/remotes/$name/$ref"
        git -C "$destination" remote set-branches --add -- "$name" "$ref"; or return
    end
    # A known commit can still be missing its remote-tracking ref.
    if not git --no-lazy-fetch -C "$destination" rev-parse --verify "$tracking_ref^{commit}" >/dev/null 2>&1
        git -C "$destination" fetch --quiet --no-recurse-submodules -- "$name" "+$branch_ref:$tracking_ref"; or return
    end
    printf '%s\n' "$tracking_ref"
end

function __ghe_pull --argument-names destination remote
    set -l changes "$(git -C "$destination" status --porcelain --untracked-files=all)"; or return
    if test -n "$changes"
        return 0
    end
    set -l branch "$(git -C "$destination" symbolic-ref -q HEAD)"; or return 0
    set -l upstream (git -C "$destination" for-each-ref --format='%(upstream:remotename)%0a%(upstream:remoteref)%0a%(upstream)' -- "$branch"); or return
    if test -z "$upstream[1]"; or test -z "$upstream[2]"; or test -z "$upstream[3]"
        printf '%s: no upstream configured; skipping pull\n' "$0" >&2
        return 0
    end

    set -l merge_ref "$upstream[3]"
    if test "$upstream[1]" != .
        set -l remotes (__gh_remotes "$remote" "$destination"); or return
        if not contains -- "$upstream[1]" $remotes
            printf '%s: upstream remote does not match the requested repository: %s\n' "$0" "$upstream[1]" >&2
            return 1
        end
        set -l upstream_ref "$(git -C "$destination" rev-parse --symbolic-full-name "$upstream[3]" 2>/dev/null)"
        if test "$upstream[3]" = "$branch"; or test "$upstream_ref" = "$branch"
            # A fetch mapping may target the checked-out local branch.
            git -C "$destination" fetch --quiet --no-recurse-submodules --refmap= -- "$upstream[1]" "$upstream[2]"; or return
            set merge_ref FETCH_HEAD
        else
            git -C "$destination" fetch --quiet --no-recurse-submodules -- "$upstream[1]" "+$upstream[2]:$upstream[3]"; or return
        end
    end
    git -C "$destination" merge --quiet --ff-only --no-squash --no-autostash --no-overwrite-ignore -- "$merge_ref"
end

function __ghe_checkout --argument-names remote destination tail line
    if test -e "$destination/.git"
        set -l root "$(git -C "$destination" rev-parse --show-toplevel)"; or return
        if test "$root" != "$(path resolve -- "$destination")"
            printf '%s: destination is not a repository root: %s\n' "$0" "$destination" >&2
            return 1
        end
        set -l remotes (__gh_remotes "$remote" "$destination"); or return
        if test (count $remotes) -eq 0
            printf '%s: destination does not match the requested repository: %s\n' "$0" "$destination" >&2
            return 1
        end
    else
        mkdir -p -- "$(path dirname -- "$destination")"; or return
        git clone -- "$remote" "$destination"; or return
    end

    set -l target "$destination"
    set -l requested_path ''
    if test -n "$tail"
        set -l resolved (__gh_resolve "$remote" "$tail" "$destination")
        test (count $resolved) -eq 4; or return 1
        set -l full_ref "$resolved[1]"
        set -l ref "$resolved[2]"
        set -l revision "$(git --no-lazy-fetch -C "$destination" rev-parse --verify "$resolved[4]^{commit}" 2>/dev/null)"
        if test -z "$revision"; and string match -qr '^[0-9a-fA-F]{4,39}$' -- "$full_ref"
            set -l name (__ghe_remote "$remote" "$destination"); or return
            set -l fetch_options
            if test "$(git -C "$destination" rev-parse --is-shallow-repository)" = true
                set fetch_options --unshallow
            end
            git -C "$destination" fetch --quiet --no-recurse-submodules $fetch_options -- "$name" "+refs/heads/*:refs/remotes/$name/*"; or return
            set revision "$(git --no-lazy-fetch -C "$destination" rev-parse --verify "$full_ref^{commit}" 2>/dev/null)"
            if test -z "$revision"
                printf '%s: commit %s is missing or ambiguous after fetching remote branches; use a longer or full commit hash\n' "$0" "$ref" >&2
                return 1
            end
        end
        set requested_path "$resolved[3]"
        set -l current_branch "$(git -C "$destination" symbolic-ref -q HEAD)"
        set -l branch_ref ''
        if string match -qr '^refs/(heads|remotes)/' -- "$full_ref"
            set branch_ref "refs/heads/$ref"
        end
        set -l checkout_needed true
        if test -n "$branch_ref"
            if test "$current_branch" = "$branch_ref"; and test "$full_ref" = "$branch_ref"; and test -n "$revision"
                set checkout_needed false
            end
        else if test -z "$current_branch"; and test -n "$revision"
            if test "$revision" = "$(git -C "$destination" rev-parse HEAD)"
                set checkout_needed false
            end
        end

        if test "$checkout_needed" = true
            set -l changes "$(git -C "$destination" status --porcelain --untracked-files=all)"; or return
            if test -n "$changes"
                printf '%s: keeping the current ref because the checkout has local changes\n' "$0" >&2
            else
                if test -n "$branch_ref"
                    if git -C "$destination" show-ref --verify --quiet "$branch_ref"
                        git -C "$destination" switch --quiet --no-overwrite-ignore -- "$ref"; or return
                    else
                        set -l name (__ghe_remote "$remote" "$destination" "$ref" "$full_ref"); or return
                        set -l tracking_ref (__ghe_tracking_ref "$name" "$destination" "$ref"); or return
                        if git -C "$destination" show-ref --verify --quiet "$branch_ref"
                            git -C "$destination" switch --quiet --no-overwrite-ignore -- "$ref"; or return
                        else
                            git -C "$destination" switch --quiet --no-overwrite-ignore --no-track --create "$ref" "$tracking_ref^{commit}"; or return
                        end
                        git -C "$destination" config --replace-all "branch.$ref.remote" "$name"; or return
                        git -C "$destination" config --replace-all "branch.$ref.merge" "$branch_ref"; or return
                    end
                else
                    # Cached tags and commits need no refresh.
                    if test -z "$revision"
                        git -C "$destination" fetch --quiet --no-recurse-submodules -- "$remote" "$full_ref"; or return
                        set revision FETCH_HEAD
                    end
                    # A commit expression prevents choosing a branch named after the OID.
                    git -C "$destination" switch --quiet --no-overwrite-ignore --detach "$revision^{commit}"; or return
                end
            end
        end
    end

    if test -n "$requested_path"
        set target "$destination/$requested_path"
        if not test -e "$target"; and not test -L "$target"
            # Existing paths open immediately, including while offline.
            # Pull only when the requested path may have been added upstream.
            __ghe_pull "$destination" "$remote"; or return
            if not test -e "$target"; and not test -L "$target"
                printf '%s: path does not exist in this checkout: %s\n' "$0" "$requested_path" >&2
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
        test -z "$line"; or set -a editor "+$line"
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
    set -l line (string match -rg '#L([0-9]+)(?:-L[0-9]+)?$' -- "$input")
    __ghe_checkout "$github[3]" "$HOME/code/$github[1]" "$github[2]" "$line"
end

function gho --argument-names target
    set -lx 0 (status current-function)
    # Opening a page must not fetch missing objects from a partial clone.
    set -lx GIT_NO_LAZY_FETCH 1
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
        if not test -L "$entry"
            set name "$(path basename -- "$(path resolve -- "$entry")")"
        end
        set repo_path "$repo_path$name"
    else if test -n "$repo_path"
        # Git's directory prefix ends in /.
        set -l parts (string split -r -m 1 / -- "$repo_path")
        set repo_path "$parts[1]"
    end

    # Named branches open the cached remote version, including when local commits are ahead.
    set -l remote
    set -l remote_ref
    set -l ref
    set -l commit
    set -l branch "$(git -C "$dir" symbolic-ref -q HEAD)"
    if test -n "$branch"
        set -l upstream (git -C "$dir" for-each-ref --format='%(upstream:remotename)%0a%(upstream:remoteref)%0a%(upstream)' -- "$branch")
        if test -n "$upstream[1]"; and test "$upstream[1]" != .
            set remote "$upstream[1]"
            if test -n "$upstream[3]"; and string match -q 'refs/heads/*' -- "$upstream[2]"
                set ref (string replace -r '\Arefs/heads/' '' -- "$upstream[2]")
                set remote_ref "$upstream[3]"
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
    set -l remote_url "$(git -C "$dir" remote get-url -- "$remote")"; or return
    set -l github (__gh_parse "$remote_url")
    test (count $github) -eq 3; or return 1
    set -l url "https://github.com/$github[1]"
    if test -z "$repo_path"; and test -n "$branch"; and not git -C "$dir" rev-parse --verify HEAD >/dev/null 2>&1
        printf '%s\n' "$url"
        open "$url"
        return
    end

    if test -n "$branch"
        if test -z "$remote_ref"
            set ref (string replace -r '\Arefs/heads/' '' -- "$branch")
            set -l refspecs (git -C "$dir" config --get-all "remote.$remote.fetch")
            set remote_ref (__gh_tracking_ref "refs/heads/$ref" $refspecs)
            test -n "$remote_ref"; or set remote_ref "refs/remotes/$remote/$ref"
        end
        set commit "$(git -C "$dir" rev-parse --verify "$remote_ref^{commit}" 2>/dev/null)"
        if test -z "$commit"
            printf '%s: branch has not been pushed or fetched yet: %s/%s\n' "$0" "$remote" "$ref" >&2
            return 1
        end
    else
        set commit "$(git -C "$dir" rev-parse --verify 'HEAD^{commit}' 2>/dev/null)"; or begin
            if test -n "$repo_path"
                printf '%s: repository has no commits\n' "$0" >&2
                return 1
            end
        end
    end
    test -n "$ref"; or set ref "$commit"
    if test -z "$remote_ref"
        set remote_ref "refs/remotes/$remote/$ref"
    end

    set -l kind tree
    if test -n "$repo_path"
        set kind "$(git -C "$dir" --literal-pathspecs ls-tree --full-tree --format='%(objecttype)' "$commit" -- "$repo_path")"; or return
        if test -z "$kind"
            if test -n "$branch"
                printf '%s: path is not in the cached remote branch; push or fetch first: %s\n' "$0" "$target" >&2
            else
                printf '%s: path is not in the current commit: %s\n' "$0" "$target" >&2
            end
            return 1
        end
        if test "$kind" != tree; and test "$kind" != blob
            printf '%s: unsupported Git object at path: %s\n' "$0" "$target" >&2
            return 1
        end
    end

    # The default-branch homepage needs no ref; other ambiguous links use the commit.
    set -l refspecs (git -C "$dir" config --get-all "remote.$remote.fetch")
    set -l default_ref "$(git -C "$dir" symbolic-ref -q "refs/remotes/$remote/HEAD" 2>/dev/null)"
    if test -n "$default_ref"
        set -l source (__gh_source_ref "$default_ref" $refspecs)
        if test -z "$source"; and string match -q "refs/remotes/$remote/*" -- "$default_ref"
            set source "refs/heads/$(string replace -- "refs/remotes/$remote/" '' "$default_ref")"
        end
        if test -n "$source"
            set -l mapped (__gh_tracking_ref "$source" $refspecs)
            test -z "$mapped"; or set default_ref "$mapped"
        end
    end
    if test -z "$default_ref"; and test -z "$repo_path"; and test -n "$branch"
        # set-head assumes refs/remotes; cache the advertised HEAD using its mapping.
        set -l advertised (git -C "$dir" ls-remote --symref -- "$remote" HEAD 2>/dev/null)
        for line in $advertised
            set -l fields (string split \t -- "$line")
            if test "$fields[2]" = HEAD; and string match -q 'ref: refs/heads/*' -- "$fields[1]"
                set -l source (string sub -s 6 -- "$fields[1]")
                set default_ref (__gh_tracking_ref "$source" $refspecs)
                test -n "$default_ref"; or set default_ref "refs/remotes/$remote/$(string replace -r '^refs/heads/' '' -- "$source")"
                git -C "$dir" symbolic-ref "refs/remotes/$remote/HEAD" "$default_ref" >/dev/null 2>&1
                break
            end
        end
    end
    if test -z "$repo_path"; and test -n "$branch"; and test "$default_ref" = "$remote_ref"
        set ref ''
    else if string match -qr '^[0-9a-fA-F]{40}$' -- "$ref"
        set ref "$commit"
    else if git -C "$dir" show-ref --verify --quiet "refs/tags/$ref"; and git -C "$dir" show-ref --verify --quiet "$remote_ref"
        set ref "$commit"
    else
        set -l resolved (__gh_resolve "$remote_url" "$kind/$ref/$repo_path" "$dir" true)
        if test (count $resolved) -ne 4; or test "$resolved[2]" != "$ref"; or test "$resolved[3]" != "$repo_path"
            set ref "$commit"
        end
    end

    set -l web_path "$ref"
    if test -n "$repo_path"
        set web_path "$web_path/$repo_path"
    end
    if test -n "$commit"; and test -n "$web_path"
        set url "$url/$kind/$(string escape --style=url -- "$web_path")"
    end
    printf '%s\n' "$url"
    open "$url"
end
