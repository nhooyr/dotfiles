function __gh_parse --argument-names input
    # Return three lines: owner/repo, the URL's remaining path, and a clone URL.
    # Reject controls before decoding can strip trailing newlines.
    if string match -rqi '%[01][0-9a-f]|%7f|[[:cntrl:]]' -- "$input"
        printf '%s: invalid input\n' "$0" >&2
        return 1
    end
    # Accept GitHub's standard ports and its alternate SSH endpoint.
    set -l http_userinfo '(?:[A-Za-z0-9._~!$&\'()*+,;=:-]|%[0-9a-f]{2})+'
    set -l http_host '(?:github\.com|raw\.githubusercontent\.com)'
    set -l path (string replace -ri "^(https://(?:$http_userinfo@)?$http_host(:443)?/|http://(?:$http_userinfo@)?$http_host(:80)?/|ssh://git@(github\\.com(:22)?|ssh\\.github\\.com:443)/|git@github\\.com:|github\\.com(:443)?/)" '' -- "$input")
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
    set -l userinfo (string match -rgi "^https?://($http_userinfo@)$http_host(?::[0-9]+)?/" -- "$input")
    set -l remote "https://$userinfo[1]github.com/$parts[1]/$repo.git"
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

function __gh_commit --argument-names destination revision
    git --no-lazy-fetch -C "$destination" rev-parse --verify --end-of-options "$revision^{commit}" 2>/dev/null
end

function __gh_local_ref --argument-names name
    # Expand an exact fetch destination the way git fetch does, even before it exists.
    switch "$name"
        case 'refs/*'
            printf '%s\n' "$name"
        case 'heads/*' 'tags/*' 'remotes/*'
            printf 'refs/%s\n' "$name"
        case '*'
            printf 'refs/heads/%s\n' "$name"
    end
end

function __gh_refspecs --argument-names name destination
    for spec in (git -C "$destination" config --get-all "remote.$name.fetch")
        set -l fields (string split -m 1 : -- "$spec")
        # Git uses pattern destinations as written.
        if test (count $fields) -eq 2; and test -n "$fields[2]"; and not string match -q '*\**' -- "$fields[2]"
            set spec "$fields[1]:$(__gh_local_ref "$fields[2]")"
        end
        printf '%s\n' "$spec"
    end
end

function __gh_map_ref --argument-names source target ref
    set -l parts (string split -m 1 '*' -- "$source")
    if test (count $parts) -eq 1
        test "$source" = "$ref"; or return 1
        printf '%s\n' "$target"
    else
        set -l pattern "^$(string escape --style=regex -- "$parts[1]")(.*)$(string escape --style=regex -- "$parts[2]")\$"
        set -l matched (string match -rg -- "$pattern" "$ref"); or return 1
        string replace -- '*' "$matched" "$target"
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
        if test (count $fields) -ne 2; or test -z "$fields[2]"
            continue
        end
        set -l source (__gh_map_ref "$fields[2]" "$fields[1]" "$ref")
        string match -q 'refs/heads/*' -- "$source"; or continue
        set -l target (__gh_tracking_ref "$source" $argv[2..]); or continue
        if test "$target" = "$ref"
            printf '%s\n' "$source"
            return 0
        end
        test -n "$fallback"; or set fallback "$source"
    end
    # A cached HEAD alias may still point at a secondary fetch destination.
    if test -n "$fallback"
        printf '%s\n' "$fallback"
        return 0
    end
    return 1
end

function __gh_cached_branches --argument-names name destination
    set -l refspecs (__gh_refspecs "$name" "$destination")
    set -l prefixes
    for spec in $refspecs
        set -l fields (string split -m 1 : -- "$spec")
        if test (count $fields) -eq 2; and test -n "$fields[2]"
            set -a prefixes (string replace -r '[^/]*\*.*$' '' -- "$fields[2]")
        end
    end
    test (count $prefixes) -gt 0; or return 0
    set -l refs (git -C "$destination" for-each-ref \
        --format='%(if)%(symref)%(then)%(else)%(refname)%(end)' -- $prefixes); or return
    for ref in $refs
        set -l source (__gh_source_ref "$ref" $refspecs); or continue
        set -l target (__gh_tracking_ref "$source" $refspecs); or continue
        test "$ref" = "$target"; or continue
        set -l branch (string replace -r '^refs/heads/' '' -- "$source")
        printf '%s\t%s\n' "refs/remotes/$name/$branch" "$ref"
    end
end

function __gh_default_ref --argument-names name destination
    # Resolve the cached remote HEAD through the configured fetch mapping.
    set -l ref "$(git -C "$destination" symbolic-ref -q "refs/remotes/$name/HEAD" 2>/dev/null)"; or return
    set -l specs $argv[3..]
    set -l source (__gh_source_ref "$ref" $specs)
    if test -z "$source"; and string match -q "refs/remotes/$name/*" -- "$ref"
        set source "refs/heads/$(string replace -- "refs/remotes/$name/" '' "$ref")"
    end
    set -l mapped (__gh_tracking_ref "$source" $specs)
    test -z "$mapped"; or set ref "$mapped"
    printf '%s\n' "$ref"
end

function __gh_is_ref_route --argument-names tail
    string match -qr '^(blob|tree|commits?|blame|tag|branch|tagfile|branchfile|oid)/.+' -- "$tail"
end

function __gh_resolve --argument-names remote tail destination cached_only
    # Return the full ref, short name, path, and a locally usable revision or OID.
    set -l route (string split -m 1 / -- "$tail")
    if not __gh_is_ref_route "$tail"
        printf '%s: expected a URL identifying a ref or file\n' "$0" >&2
        return 1
    end
    set -l namespace ''
    switch "$route[1]"
        case tag tagfile
            set namespace refs/tags
        case branch branchfile
            set namespace refs/heads
        case oid
            string match -qr '^[0-9a-fA-F]{4,40}$' -- "$route[2]"; or return 1
            printf '%s\n' "$route[2]" "$route[2]" '' "$route[2]"
            return 0
    end
    set -l exact false
    if contains -- "$route[1]" tag branch
        if not git check-ref-format "$namespace/$route[2]"
            printf '%s: invalid ref name: %s\n' "$0" "$route[2]" >&2
            return 1
        end
        set exact true
    end
    # Commit URLs must stay unambiguous even when a ref has the same name.
    set -l commit_path (string split -m 1 / -- "$route[2]")
    if test -z "$namespace"; and string match -qr '^[0-9a-fA-F]{40}$' -- "$commit_path[1]"
        printf '%s\n' "$commit_path[1]" "$commit_path[1]" (string trim -r -c / -- "$commit_path[2]") "$commit_path[1]"
        return 0
    end
    # Prefer local refs, including cached branches from the requested repository.
    set -l prefixes refs/tags refs/heads
    test -z "$namespace"; or set prefixes "$namespace"
    set -l source_prefixes $prefixes
    # Symbolic aliases such as origin/HEAD aren't branch names to check out.
    set -l refs (git -C "$destination" for-each-ref \
        --format='%(if)%(symref)%(then)%(else)%(refname)%(end)' $prefixes); or return
    set -l revisions $refs
    set -l remotes (__gh_remotes "$remote" "$destination"); or return
    for name in $remotes
        test "$namespace" != refs/tags; or continue
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
            set -l query_remote "$remote"
            set -q remotes[1]; and set query_remote "$remotes[1]"
            set -l advertised (git -C "$destination" ls-remote --refs --heads --tags -- "$query_remote"); or return
            set refs (string split -f 2 \t -- $advertised)
            set revisions (string split -f 1 \t -- $advertised)
            set prefixes $source_prefixes
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
            if test -z "$namespace"; and test "$ref" = HEAD; and test "$cached_only" != true
                set -l revision (__ghe_compare_ref "$remote" "$destination" HEAD true); or return
                printf '%s\n' "$revision" "$revision" (string trim -r -c / -- "$path") "$revision"
                return 0
            end
            if test -z "$namespace"; and string match -qr '^[0-9a-fA-F]{4,39}$' -- "$ref"
                # A short hex name may be a branch, such as 2026/fix.
                if test "$source" = remote; or __gh_commit "$destination" "$ref" >/dev/null
                    printf '%s\n' "$ref" "$ref" (string trim -r -c / -- "$path") "$ref"
                    return 0
                end
            end
            test "$exact" = false; or break
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
    set -l refspecs (__gh_refspecs "$name" "$destination")
    set -l tracking_ref (__gh_tracking_ref "$branch_ref" $refspecs)
    set -l mapping_status "$status"
    if test "$mapping_status" -eq 2
        printf '%s: branch is excluded by the remote fetch configuration: %s/%s\n' "$0" "$name" "$ref" >&2
        return 1
    else if test -z "$tracking_ref"
        set tracking_ref "refs/remotes/$name/$ref"
    end
    if git -C "$destination" symbolic-ref -q "$tracking_ref" >/dev/null 2>&1
        printf '%s: fetch destination is symbolic: %s\n' "$0" "$tracking_ref" >&2
        return 1
    end
    if test "$mapping_status" -ne 0
        # Single-branch clones need a mapping for future fetches, too.
        git -C "$destination" remote set-branches --add -- "$name" "$ref"; or return
    end
    # A known commit can still be missing its remote-tracking ref.
    if not __gh_commit "$destination" "$tracking_ref" >/dev/null
        git -C "$destination" fetch --quiet --no-recurse-submodules --refmap= -- "$name" "+$branch_ref:$tracking_ref"; or return
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
        # Skip mappings into checked-out branches; merge updates this worktree safely.
        set -l checked_out_refs (git -C "$destination" for-each-ref \
            --format='%(if)%(worktreepath)%(then)%(refname)%(end)' refs/heads); or return
        set -l refspecs (__gh_refspecs "$upstream[1]" "$destination")
        set -l refmap_options
        set -l skipped false
        for spec in $refspecs
            set -l fields (string split -m 1 : -- (string replace -r '^\+' '' -- "$spec"))
            if test (count $fields) -eq 2; and test -n "$fields[2]"
                # Exact targets need no source match, including abbreviated sources.
                set -l target "$fields[2]"
                if string match -q '*\**' -- "$target"
                    set target (__gh_map_ref "$fields[1]" "$target" "$upstream[2]")
                end
                if test -n "$target"
                    set -l canonical "$(git -C "$destination" rev-parse --symbolic-full-name "$target" 2>/dev/null)"
                    if contains -- "$target" $checked_out_refs; or contains -- "$canonical" $checked_out_refs
                        set skipped true
                        continue
                    end
                end
            end
            set -a refmap_options "--refmap=$spec"
        end
        if test "$skipped" = false
            set refmap_options
        else if test (count $refmap_options) -eq 0
            set refmap_options --refmap=
        end
        git -C "$destination" fetch --quiet --no-recurse-submodules $refmap_options -- "$upstream[1]" "$upstream[2]"; or return
        set merge_ref FETCH_HEAD
    end
    git -C "$destination" merge --quiet --ff-only --no-squash --no-autostash --no-overwrite-ignore -- "$merge_ref"
end

function __gh_commit_prefix --argument-names destination prefix fetch_head
    # Resolve abbreviated object IDs without consulting local ref names.
    set -l matches
    for object in (git --no-lazy-fetch -C "$destination" rev-parse --disambiguate="$prefix")
        set -l commit "$(__gh_commit "$destination" "$object")"
        test -n "$commit"; or continue
        if test -n "$fetch_head"
            # Resolve fork-qualified prefixes only among the fetched histories.
            set -l outside (string replace -r '^([^\t]+)\t.*$' '^$1' < "$fetch_head" | git --no-lazy-fetch -C "$destination" rev-list --max-count=1 "$commit" --stdin); or return
            test -z "$outside"; or continue
            if test "$object" != "$commit"
                # A local tag may peel to a fetched commit without belonging to the fork.
                set -l fetched (
                    string split -f 1 \t < "$fetch_head" | git --no-lazy-fetch -C "$destination" rev-list --objects --no-object-names --max-count=0 --filter=tree:0 --stdin | string match -- "$object"
                    test "$pipestatus[2]" -eq 0
                ); or return
                test -n "$fetched"; or continue
            end
            contains -- "$commit" $matches; and continue
        end
        set -a matches "$commit"
    end
    test (count $matches) -eq 1; or return 1
    printf '%s\n' "$matches[1]"
end

function __ghe_fetch_history --argument-names destination remote
    # Explicit refs, or all advertised histories when resolving a short OID.
    set -l refs $argv[3..]
    if not set -q refs[1]
        set -l advertised (git -C "$destination" ls-remote --refs --heads --tags -- "$remote"); or return
        set refs (string split -f 2 \t -- $advertised)
    end
    if not set -q refs[1]
        printf '%s: remote advertises no branch or tag histories\n' "$0" >&2
        return 1
    end
    set -l options
    if test "$(git -C "$destination" rev-parse --is-shallow-repository)" = true
        set options --unshallow
    end
    # Keep fetch.pruneTags from adding unrelated tags to this explicit fetch.
    printf '%s\n' $refs | git -C "$destination" fetch --quiet --no-tags --no-recurse-submodules --no-prune-tags --refmap= $options --stdin -- "$remote"
end

function __gh_cache_refs --argument-names destination cache source
    # Request names only have hashed keys; old formats stored canonical sources.
    set -l key "$(printf '%s\n' "$source" | git -C "$destination" hash-object --stdin)"; or return
    printf '%s\n' "$cache/by-ref/$key"
    switch "$source"
        case HEAD 'refs/heads/*' 'refs/tags/*'
            printf '%s\n' "$cache/$(string escape --style=var -- "$source")" "$cache/$source"
    end
end

function __ghe_compare_ref --argument-names remote destination ref prefer_cached
    # Fork-qualified refs use owner:branch or owner:repository:branch.
    set -l qualified false
    if string match -q '*:*' -- "$ref"
        set qualified true
        set -l github (__gh_parse "$remote"); or return
        set -l parts (string split -m 2 : -- "$ref")
        set -l repo (string split -m 1 / -- "$github[1]")[2]
        if test (count $parts) -eq 3
            set repo "$parts[2]"
        end
        set -l fork (__gh_parse "$parts[1]/$repo"); or return
        set remote (string replace -r '[^/:]+/[^/]+\.git$' "$fork[1].git" -- "$remote")
        set ref "$parts[-1]"
    end

    set -l ancestry (string match -rg '((?:[~^][0-9]*)+)$' -- "$ref")
    set ref (string replace -r '(?:[~^][0-9]*)+$' '' -- "$ref")
    set ref (string replace -r '^(heads|tags)/' 'refs/$1/' -- "$ref")
    set -l sources "$ref"
    switch "$ref"
        case 'refs/heads/*' 'refs/tags/*' HEAD
        case '*'
            set sources "refs/heads/$ref" "refs/tags/$ref"
    end
    set -l remotes (__gh_remotes "$remote" "$destination"); or return
    set -l query "$remote"
    set -q remotes[1]; and set query "$remotes[1]"
    set -l github (__gh_parse "$remote"); or return
    set -l identity (string lower -- "$github[1]" | git -C "$destination" hash-object --stdin); or return
    set -l cache "refs/gh/compare/$identity"
    set -l candidates
    if string match -qr '^[0-9a-fA-F]{40}$' -- "$ref"
        set candidates "$ref"
    else
        # Remember which source an unqualified name last selected, including branch/tag changes.
        set candidates (__gh_cache_refs "$destination" "$cache" "$ref"); or return
        for source in $sources
            if test "$source" != "$ref"
                set -a candidates (__gh_cache_refs "$destination" "$cache" "$source"); or return
            end
            switch "$source"
                case HEAD 'refs/heads/*'
                    for name in $remotes
                        set -l specs (__gh_refspecs "$name" "$destination")
                        set -l tracking
                        if test "$source" = HEAD
                            set tracking (__gh_default_ref "$name" "$destination" $specs)
                        else
                            set tracking (__gh_tracking_ref "$source" $specs)
                        end
                        test -z "$tracking"; or set -a candidates "$tracking"
                    end
                case 'refs/tags/*'
                    test "$qualified" != false; or set -a candidates "$source"
            end
        end
    end
    set -l oid
    for candidate in $candidates
        # Symbolic cache aliases can point at an unrelated branch.
        git -C "$destination" symbolic-ref -q "$candidate" >/dev/null 2>&1; and continue
        set oid "$(__gh_commit "$destination" "$candidate")"
        test -z "$oid"; or break
    end
    if test -n "$oid"
        if test "$prefer_cached" = true; or string match -qr '^[0-9a-fA-F]{40}$' -- "$ref"
            __gh_commit "$destination" "$oid$ancestry[1]"
            return $status
        end
    else if test "$qualified" = false; and string match -qr '^[0-9a-fA-F]{4,39}$' -- "$ref"
        # Only a prefix without a known named ref is immutable and needs no refresh.
        set oid (__gh_commit_prefix "$destination" "$ref")
        if test -n "$oid"
            __gh_commit "$destination" "$oid$ancestry[1]"
            return $status
        end
    end

    set -l fetch_refs "$ref"
    set -l fetch_status 0
    if not string match -qr '^[0-9a-fA-F]{40}$' -- "$ref"
        # Status 2 means the remote answered but the requested name is absent.
        set -l advertised (git -C "$destination" ls-remote --exit-code -- "$query" $sources)
        set fetch_status "$status"
        if contains -- "$fetch_status" 0 2
            set fetch_refs
            set -l refs (string split -f 2 \t -- $advertised)
            for source in $sources
                if contains -- "$source" $refs
                    set fetch_refs "$source"
                    break
                end
            end
            if not set -q fetch_refs[1]
                if test -n "$oid"; or not string match -qr '^[0-9a-fA-F]{4,39}$' -- "$ref"
                    printf '%s: no branch, tag, or commit matches comparison ref: %s\n' "$0" "$ref" >&2
                    return 1
                end
            end
            # An unresolved short OID needs all advertised histories.
            set fetch_status 0
        end
    end
    if test "$fetch_status" -eq 0
        __ghe_fetch_history "$destination" "$query" $fetch_refs
        set fetch_status "$status"
    end
    if test "$fetch_status" -ne 0
        test -n "$oid"; or return "$fetch_status"
        printf '%s: could not refresh comparison ref; using cached commit: %s\n' "$0" "$ref" >&2
        __gh_commit "$destination" "$oid$ancestry[1]"
        return $status
    end

    if not set -q fetch_refs[1]
        set -l fetch_head ''
        if test "$qualified" = true
            set fetch_head "$(git -C "$destination" rev-parse --path-format=absolute --git-path FETCH_HEAD)"; or return
        end
        set oid (__gh_commit_prefix "$destination" "$ref" "$fetch_head")
    else
        set oid "$(__gh_commit "$destination" FETCH_HEAD)"
    end
    if test -z "$oid"
        printf '%s: comparison commit is missing or ambiguous: %s\n' "$0" "$ref" >&2
        return 1
    end
    if set -q fetch_refs[1]
        set -l cache_sources "$ref"
        contains -- "$fetch_refs[1]" $cache_sources; or set -a cache_sources "$fetch_refs[1]"
        for source in $cache_sources
            set -l cache_refs (__gh_cache_refs "$destination" "$cache" "$source"); or return
            git -C "$destination" update-ref --no-deref "$cache_refs[1]" "$oid"; or return
        end
    end
    __gh_commit "$destination" "$oid$ancestry[1]"
end

function __ghe_compare --argument-names remote destination comparison
    test -n "$comparison"; or return 0
    set -l range (string split -m 1 ... -- "$comparison")
    set -l dots ...
    if test (count $range) -ne 2
        set range (string split -m 1 .. -- "$comparison")
        set dots ..
    end
    if test (count $range) -ne 2
        set range HEAD "$comparison"
        set dots ...
    end
    test -n "$range[1]"; or set range[1] HEAD
    test -n "$range[2]"; or set range[2] HEAD
    set -l base (__ghe_compare_ref "$remote" "$destination" "$range[1]"); or return
    set -l head (__ghe_compare_ref "$remote" "$destination" "$range[2]"); or return
    if test "$dots" = ...
        if not git --no-lazy-fetch -C "$destination" merge-base "$base" "$head" >/dev/null 2>&1
            printf '%s: comparison has no local merge base; fetch more history or use a two-dot comparison\n' "$0" >&2
            return 1
        end
        git -C "$destination" diff "$base...$head" --
    else
        git -C "$destination" diff "$base" "$head" --
    end
end

function __ghe_url_route --argument-names repository tail
    switch "$tail"
        case 'raw/refs/heads/*'
            string replace -r '^raw/refs/heads/' branchfile/ -- "$tail"
        case 'raw/refs/tags/*'
            string replace -r '^raw/refs/tags/' tagfile/ -- "$tail"
        case 'raw/*' 'edit/*'
            string replace -r '^(raw|edit)/' blob/ -- "$tail"
        case 'releases/tag/*'
            string replace -r '^releases/tag/' tag/ -- "$tail"
        case releases/latest
            set -l tag "$(gh api --hostname github.com "repos/$repository/releases/latest" --jq '.tag_name | select(type == "string" and length > 0)')"; or return
            if test -z "$tag"; or not git check-ref-format "refs/tags/$tag" >/dev/null 2>&1
                printf '%s: latest release has no valid tag\n' "$0" >&2
                return 1
            end
            printf 'tag/%s\n' "$tag"
        case 'archive/*'
            set -l ref (string sub -s 9 -- "$tail")
            set ref (string replace -r '\.(zip|tar\.gz)$' '' -- "$ref"); or return 0
            switch "$ref"
                case 'refs/heads/*'
                    string replace -r '^refs/heads/' branch/ -- "$ref"
                case 'refs/tags/*'
                    string replace -r '^refs/tags/' tag/ -- "$ref"
                case '*'
                    if string match -qr '^[0-9a-fA-F]{4,40}$' -- "$ref"
                        printf 'oid/%s\n' "$ref"
                    else
                        # Older archive links name the branch or tag without refs/.
                        printf 'tree/%s\n' "$ref"
                    end
            end
        case 'tag/*' 'branch/*' 'tagfile/*' 'branchfile/*' 'oid/*'
            # These routes are internal results, not GitHub page URLs.
            return 0
        case '*'
            printf '%s\n' "$tail"
    end
end

function __ghe_pull_request --argument-names remote destination number
    string match -qr '^[1-9][0-9]*$' -- "$number"; or return 1
    set -l name (__ghe_remote "$remote" "$destination"); or return
    # Remote names can change or be reused for another repository.
    set -l github (__gh_parse "$remote"); or return
    set -l identity (string lower -- "$github[1]" | git -C "$destination" hash-object --stdin); or return
    set -l cache "refs/gh/pull/$identity/$number/head"
    # Pull requests move, so refresh the head before falling back to the cache.
    if git -C "$destination" fetch --quiet --no-tags --no-recurse-submodules --refmap= -- "$name" "refs/pull/$number/head"
        set -l revision "$(__gh_commit "$destination" FETCH_HEAD)"; or return
        git -C "$destination" update-ref --no-deref "$cache" "$revision"; or return
        printf '%s\n' "$revision"
        return
    end
    # A symbolic cache would read some other ref, so only a direct one counts.
    git -C "$destination" symbolic-ref -q "$cache" >/dev/null 2>&1; and return 1
    __gh_commit "$destination" "$cache"
end

function __ghe_open --argument-names target line column end_line end_column
    if test -d "$target"; and not test -L "$target"
        cd -- "$target"
        return $status
    end
    cd -- "$(path dirname -- "$target")"; or return
    if test -z "$EDITOR"
        printf '%s: EDITOR is not set\n' "$0" >&2
        return 1
    end
    # Respect quoted arguments in EDITOR without evaluating shell commands.
    printf '%s\n' "$EDITOR" | read --tokenize --array --local editor; or return
    if test (count $editor) -eq 0
        printf '%s: EDITOR is empty\n' "$0" >&2
        return 1
    end
    if test -n "$end_line"
        set -l selection V
        if test -n "$column"; or test -n "$end_column"
            set selection v
            test -n "$end_column"; or set end_column "max([1, strlen(getline($end_line))])"
        else
            set end_column 1
        end
        test -n "$column"; or set column 1
        set -a editor "+set selection=inclusive | call cursor($line, $column) | execute 'normal! $selection' | call cursor($end_line, $end_column)"
    else if test -n "$column"
        set -a editor "+call cursor($line, $column)"
    else if test -n "$line"
        set -a editor "+$line"
    end
    $editor "$target"
end

function __ghe_switch --argument-names remote destination full_ref ref revision
    if string match -qr '^[0-9a-fA-F]{4,40}$' -- "$full_ref"
        set revision (__gh_commit_prefix "$destination" "$full_ref")
    else
        set revision "$(__gh_commit "$destination" "$revision")"
    end
    set -l current_branch "$(git -C "$destination" symbolic-ref -q HEAD)"
    set -l branch_ref ''
    if string match -qr '^refs/(heads|remotes)/' -- "$full_ref"
        set branch_ref "refs/heads/$ref"
        if git -C "$destination" symbolic-ref -q "$branch_ref" >/dev/null 2>&1
            printf '%s: local branch is symbolic: %s\n' "$0" "$branch_ref" >&2
            return 1
        end
        if test "$current_branch" = "$branch_ref"; and test "$full_ref" = "$branch_ref"; and test -n "$revision"
            return 0
        end
    else if test -z "$current_branch"; and test -n "$revision"
        if test "$revision" = "$(git -C "$destination" rev-parse HEAD)"
            return 0
        end
    end

    set -l changes "$(git -C "$destination" status --porcelain --untracked-files=all)"; or return
    if test -n "$changes"
        printf '%s: keeping the current ref because the checkout has local changes\n' "$0" >&2
        return 0
    end
    set -l switch_args
    set -l name
    if test -n "$branch_ref"
        set switch_args -- "$ref"
        if not git -C "$destination" show-ref --verify --quiet "$branch_ref"
            set name (__ghe_remote "$remote" "$destination" "$ref" "$full_ref"); or return
            set -l tracking_ref (__ghe_tracking_ref "$name" "$destination" "$ref"); or return
            # Fetch mappings can create the local branch, too.
            if not git -C "$destination" show-ref --verify --quiet "$branch_ref"
                set switch_args --no-track --create "$ref" "$tracking_ref^{commit}"
            end
        end
    else
        # Cached tags and commits need no refresh.
        if test -z "$revision"
            set -l fetch_remote (__ghe_remote "$remote" "$destination"); or return
            if string match -qr '^[0-9a-fA-F]{4,39}$' -- "$full_ref"
                __ghe_fetch_history "$destination" "$fetch_remote"; or return
                set revision (__gh_commit_prefix "$destination" "$full_ref")
                if test -z "$revision"
                    printf '%s: commit %s is missing or ambiguous after fetching remote refs; use a longer or full commit hash\n' "$0" "$ref" >&2
                    return 1
                end
            else
                git -C "$destination" fetch --quiet --no-recurse-submodules --refmap= -- "$fetch_remote" "$full_ref"; or return
                set revision FETCH_HEAD
            end
        end
        # A commit expression prevents choosing a branch named after the OID.
        set switch_args --detach "$revision^{commit}"
    end
    git -C "$destination" switch --quiet --no-overwrite-ignore $switch_args; or return
    if test -n "$name"
        git -C "$destination" config --replace-all "branch.$ref.remote" "$name"; or return
        git -C "$destination" config --replace-all "branch.$ref.merge" "$branch_ref"; or return
    end
end

function __ghe_checkout --argument-names remote destination tail line column end_line end_column
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
        set -l org_dir "$(path dirname -- "$destination")"
        set -l created_org false
        if not test -d "$org_dir"
            mkdir -p -- "$(path dirname -- "$org_dir")"; or return
            mkdir -- "$org_dir"; or return
            set created_org true
        end
        git clone -- "$remote" "$destination"; or begin
            set -l result "$status"
            if test "$created_org" = true
                rmdir -- "$org_dir"
            end
            return "$result"
        end
    end

    set -l github (__gh_parse "$remote")
    set tail "$(__ghe_url_route "$github[1]" "$tail")"; or return
    if string match -qr '^compare(/|$)' -- "$tail"
        cd -- "$destination"; or return
        __ghe_compare "$remote" "$destination" (string replace -r '^compare/?' '' -- "$tail")
        return $status
    end
    if string match -qr '^pull/[1-9][0-9]*(/|$)' -- "$tail"
        set -l request (string split / -- "$tail")
        if contains -- "$request[3]" changes files
            cd -- "$destination"; or return
            set -l revisions (gh api --hostname github.com "repos/$github[1]/pulls/$request[2]" --jq '.base.sha, .head.sha'); or return
            if test (count $revisions) -ne 2; or string match -qvr '^[0-9a-fA-F]{40}$' -- $revisions
                printf '%s: pull request has an invalid base or head commit\n' "$0" >&2
                return 1
            end
            # Cached tips in a shallow clone can still be missing their merge base.
            if test "$(git -C "$destination" rev-parse --is-shallow-repository)" = true
                set -l name (__ghe_remote "$remote" "$destination"); or return
                __ghe_fetch_history "$destination" "$name" $revisions; or return
            end
            __ghe_compare "$remote" "$destination" "$revisions[1]...$revisions[2]"
            return $status
        else if test "$request[3]" = commits; and string match -qr '^[0-9a-fA-F]{40}$' -- "$request[4]"
            set tail "oid/$request[4]"
        else
            set -l revision (__ghe_pull_request "$remote" "$destination" "$request[2]"); or return
            set tail "oid/$revision"
        end
    end
    # Other GitHub pages, such as issues, open the repository.
    __gh_is_ref_route "$tail"; or set tail ''

    set -l requested_path ''
    if test -n "$tail"
        set -l resolved (__gh_resolve "$remote" "$tail" "$destination")
        test (count $resolved) -eq 4; or return 1
        set requested_path "$resolved[3]"
        __ghe_switch "$remote" "$destination" "$resolved[1]" "$resolved[2]" "$resolved[4]"; or return
    end

    if test -z "$requested_path"
        cd -- "$destination"
        return $status
    end
    set -l target "$destination/$requested_path"
    if not test -e "$target"; and not test -L "$target"
        # Pull only when a path is missing; existing paths open offline.
        __ghe_pull "$destination" "$remote"; or return
        if not test -e "$target"; and not test -L "$target"
            printf '%s: path does not exist in this checkout: %s\n' "$0" "$requested_path" >&2
            return 1
        end
    end
    __ghe_open "$target" "$line" "$column" "$end_line" "$end_column"
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
    set -l line ''
    set -l column ''
    set -l end_line ''
    set -l end_column ''
    string match -qr '#L(?<line>[0-9]+)(?:C(?<column>[0-9]+))?(?:-L(?<end_line>[0-9]+)(?:C(?<end_column>[0-9]+))?)?$' -- "$input"
    for position in line column end_line end_column
        set "$position" (string replace -r '^0+(?=[0-9])' '' -- "$$position")
    end
    __ghe_checkout "$github[3]" "$HOME/code/$github[1]" "$github[2]" "$line" "$column" "$end_line" "$end_column"
end

function __gho_url --argument-names target
    # Resolving a page must not fetch missing objects from a partial clone.
    set -lx GIT_NO_LAZY_FETCH 1

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
        set url "$url$(string match -r '[?#].*$' -- "$target")"
        printf '%s\n' "$url"
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
            __gho_url "$resolved"
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
        set repo_path (string trim -r -c / -- "$repo_path")
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
            set remote_ref "$upstream[3]"
            if test -n "$remote_ref"; and string match -q 'refs/heads/*' -- "$upstream[2]"
                set ref (string replace -r '\Arefs/heads/' '' -- "$upstream[2]")
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
        return
    end

    set -l refspecs (__gh_refspecs "$remote" "$dir")
    if test -n "$branch"
        # %(upstream) prints abbreviated fetch destinations as written.
        test -z "$remote_ref"; or set remote_ref (__gh_local_ref "$remote_ref")
        if test -z "$remote_ref"
            set ref (string replace -r '\Arefs/heads/' '' -- "$branch")
            set remote_ref (__gh_tracking_ref "refs/heads/$ref" $refspecs)
            test -n "$remote_ref"; or set remote_ref "refs/remotes/$remote/$ref"
        end
        if git -C "$dir" symbolic-ref -q "$remote_ref" >/dev/null 2>&1
            printf '%s: cached remote branch is symbolic: %s\n' "$0" "$remote_ref" >&2
            return 1
        end
        set commit "$(__gh_commit "$dir" "$remote_ref")"
        if test -z "$commit"
            printf '%s: branch has not been pushed or fetched yet: %s/%s\n' "$0" "$remote" "$ref" >&2
            return 1
        end
    else
        set commit "$(__gh_commit "$dir" HEAD)"; or begin
            if test -n "$repo_path"
                printf '%s: repository has no commits\n' "$0" >&2
                return 1
            end
        end
    end
    test -n "$ref"; or set ref "$commit"

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
    set -l default_ref "$(__gh_default_ref "$remote" "$dir" $refspecs)"
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
    else if git -C "$dir" show-ref --verify --quiet "refs/tags/$ref"
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
end

function gho --argument-names target
    set -lx 0 (status current-function)
    if test (count $argv) -gt 1
        printf 'Usage: %s [path | owner/repo | github-url]\n' "$0" >&2
        return 1
    end
    set -q argv[1]; or set target "$PWD"
    set -l url "$(__gho_url "$target")"; or return
    printf '%s\n' "$url"
    open "$url"
end
