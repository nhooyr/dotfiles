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
    set -l is_url true
    set -l path (string replace -ri "^(https://(?:$http_userinfo@)?$http_host(:443)?/|http://(?:$http_userinfo@)?$http_host(:80)?/|ssh://git@(github\\.com(:22)?|ssh\\.github\\.com:443)/|git@github\\.com:|github\\.com(:443)?/)" '' -- "$input"); or set is_url false
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
    # Browsers can display and copy IRIs, but URL unescaping accepts only ASCII.
    for text in (string match -ar '[^\x00-\x7f]+' -- "$parts[3]")
        set parts[3] (string replace -- "$text" (string escape --style=url -- "$text") "$parts[3]")
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

function __gh_ref_spelling_safe --argument-names destination ref
    __gh_ref_path_exact "$destination" "$ref"; or return
    set -l existing (git -C "$destination" for-each-ref --ignore-case --format='%(refname)' -- "$ref"); or return
    set -l aliases (string match -i -- "$ref" $existing | string match -v -- "$ref")
    set -q aliases[1]; or return 0
    __gh_ref_paths_distinct "$destination"
end

function __gh_ref_paths_distinct --argument-names destination
    # A reftable stores ref names independently of filesystem case folding.
    set -l storage "$(git -C "$destination" config --local --get extensions.refStorage)"; or test "$status" -eq 1; or return
    test "$storage" != reftable; or return 0
    set -l refs_dir "$(git -C "$destination" rev-parse --path-format=absolute --git-path refs)"; or return
    test -d "$refs_dir"; or return 1
    not test "$refs_dir" -ef "$refs_dir/../REFS"
end

function __gh_commit --argument-names destination revision direct
    if string match -q 'refs/*' -- "$revision"
        # Enumerate the exact spelling: a loose case alias can shadow a packed ref.
        set -l format '%(refname)%09%(objectname)'
        if test "$direct" = direct
            set format '%(if)%(symref)%(then)%(else)'"$format"'%(end)'
        end
        set -l refs (git --no-lazy-fetch -C "$destination" for-each-ref --format="$format" -- "$revision" 2>/dev/null); or return
        set revision (string match -rg "^$(string escape --style=regex -- "$revision")\t([0-9a-f]+)\$" -- $refs); or return
    end
    git --no-lazy-fetch -C "$destination" rev-parse --verify --end-of-options "$revision^{commit}" 2>/dev/null
end

function __gh_direct_commit --argument-names destination
    # Use the first direct ref or immutable object ID that resolves to a commit.
    for ref in $argv[2..]
        __gh_commit "$destination" "$ref" direct; and return
    end
    return 1
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
        if test -n "$fields[2]"; and not string match -q '*\**' -- "$fields[2]"
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
        test -n "$fields[2]"; or continue
        set -l target (__gh_map_ref "$fields[1]" "$fields[2]" "$ref")
        test -n "$target"; or continue
        printf '%s\n' "$target"
        return 0
    end
    return 1
end

function __gh_source_ref --argument-names ref
    set -l owner
    # A selective fetch can write a positive mapping despite a negative refspec.
    for spec in $argv[2..]
        set -l fields (string split -m 1 : -- (string replace -r '^\+' '' -- "$spec"))
        test -n "$fields[2]"; or continue
        set -l source (__gh_map_ref "$fields[2]" "$fields[1]" "$ref"); or continue
        test -n "$source"; or set source HEAD
        if set -q owner[1]; and test "$source" != "$owner"
            printf 'both %s and %s\n' "$owner" "$source"
            return 2
        end
        set owner "$source"
    end
    set -q owner[1]; or return 1
    printf '%s\n' "$owner"
end

function __gh_tracking_source --argument-names name destination ref
    set -l source (__gh_source_ref "$ref" $argv[4..])
    set -l source_status "$status"
    if test "$source_status" -eq 2
        printf '%s\n' "$source"
        return 2
    end

    # Another remote can write the same destination. Sharing is safe only
    # when both remotes fetch the same source from the same GitHub repository.
    set -l matching_remotes
    for other in (git -C "$destination" remote)
        set -l specs
        if test "$other" = "$name"
            set specs $argv[4..]
        else
            set specs (__gh_refspecs "$other" "$destination")
        end
        for spec in $specs
            set -l target (string split -m 1 -f 2 : -- "$spec")
            if string match -iq -- "$target" "$ref"
                and not string match -q -- "$target" "$ref"
                and not __gh_ref_paths_distinct "$destination"
                printf 'remote %s (case-folded destination %s)\n' "$other" "$target"
                return 2
            end
        end
        test "$other" != "$name"; or continue
        set -l other_source (__gh_source_ref "$ref" $specs)
        test -n "$other_source"; or continue
        if test "$other_source" = "$source"
            if not set -q matching_remotes[1]
                set -l url "$(git -C "$destination" remote get-url -- "$name")"; or return
                set matching_remotes "$name" (__gh_remotes "$url" "$destination")
            end
            contains -- "$other" $matching_remotes; and continue
        end
        printf 'remote %s (%s)\n' "$other" "$other_source"
        return 2
    end
    test "$source_status" -eq 0; or return "$source_status"
    printf '%s\n' "$source"
end

function __gh_cached_branches --argument-names name destination
    set -l refspecs (__gh_refspecs "$name" "$destination")
    set -l mappings
    for branch in $argv[3..]
        set -l target (__gh_tracking_ref "refs/heads/$branch" $refspecs); or continue
        set -a mappings "$branch"\t"$target"
    end
    set -q mappings[1]; or return 0
    set -l targets (string split -f 2 \t -- $mappings)
    set -l refs (git -C "$destination" for-each-ref \
        --format='%(if)%(symref)%(then)%(else)%(refname)%(end)' -- $targets); or return
    for mapping in $mappings
        set -l fields (string split -m 1 \t -- "$mapping")
        set -l branch "$fields[1]"
        set -l target "$fields[2]"
        contains -- "$target" $refs; or continue
        __gh_mapped_alias_for "$destination" "$target" >/dev/null; and continue
        test "$(__gh_tracking_source "$name" "$destination" "$target" $refspecs)" = "refs/heads/$branch"; or continue
        printf '%s\t%s\n' "refs/remotes/$name/$branch" "$target"
    end
end

function __gh_ref_path_exact --argument-names destination ref
    # Filesystems can alias paths that Git's case-insensitive matching misses.
    string match -q 'refs/*' -- "$ref"; or return 0
    set -l dir "$(git -C "$destination" rev-parse --path-format=absolute --git-path refs)"; or return
    for component in (string split / -- (string sub -s 6 -- "$ref"))
        set -l entry "$dir/$component"
        if not test -e "$entry"; and not test -L "$entry"
            return 0
        end
        set -l entries "$dir/$component"*
        contains -- "$entry" $entries; or return 1
        set dir "$entry"
    end
    return 0
end

function __gh_default_ref --argument-names name destination
    # Resolve the cached remote HEAD through the configured fetch mapping.
    set -l specs $argv[3..]
    set -l alias "refs/remotes/$name/HEAD"
    __gh_ref_path_exact "$destination" "$alias"; or return
    set -l ref "$(git -C "$destination" symbolic-ref -q "$alias" 2>/dev/null)"; or begin
        # An exact fetch mapping can use the default name as a direct destination.
        set ref "$alias"
        __gh_commit "$destination" "$ref" >/dev/null; or return
        set -l source (__gh_tracking_source "$name" "$destination" "$ref" $specs); or return
        string match -q 'refs/heads/*' -- "$source"; or return 1
        contains -- "$source:$ref" (string replace -r '^\+' '' -- $specs); or return 1
        test "$(__gh_tracking_ref "$source" $specs)" = "$ref"; or return 1
        printf '%s\n' "$ref"
        return 0
    end
    __gh_head_alias_reserved "$destination" "$name"; and return 1
    set -l source (__gh_tracking_source "$name" "$destination" "$ref" $specs)
    if test -n "$source"
        string match -q 'refs/heads/*' -- "$source"; or return 1
    else if string match -q "refs/remotes/$name/*" -- "$ref"
        set source "refs/heads/$(string replace -- "refs/remotes/$name/" '' "$ref")"
    end
    set -l mapped (__gh_tracking_ref "$source" $specs)
    test "$status" -ne 2; or return 1
    test -z "$mapped"; or set ref "$mapped"
    printf '%s\n' "$ref"
end

function __gh_is_ref_route --argument-names tail
    string match -qr '^(blob|tree|commits?|blame|tag|branch|oid)/.+' -- "$tail"
end

function __gh_advertised_head
    string match -rg '^ref: (refs/heads/[^\t]+)\tHEAD$' -- $argv
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
        case tag
            set namespace refs/tags
        case branch
            set namespace refs/heads
        case blob tree blame commits
            if string match -qr '^refs/(heads|tags)/.' -- "$route[2]"
                set -l qualified (string split -m 2 / -- "$route[2]")
                set namespace "refs/$qualified[2]"
                set route[2] "$qualified[3]"
            end
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
    # Ref names can contain slashes, so each leading part of the path may name a branch.
    set -l names "$route[2]"
    while test "$exact" = false; and set -l shorter (string split -r -m 1 -f 1 / -- "$names[-1]")
        set -a names "$shorter"
    end
    # These glob characters can occur in a path, but never in a ref.
    set -l ref_names (string match -vr '[*?\x5b\x5c]' -- $names)
    set -l patterns $prefixes/$ref_names
    set -l refs
    if set -q patterns[1]
        # Symbolic aliases such as origin/HEAD aren't branch names to check out.
        set refs (git -C "$destination" for-each-ref \
            --format='%(if)%(symref)%(then)%(else)%(refname)%(end)' -- $patterns); or return
    end
    set -l revisions $refs
    set -l remotes (__gh_remotes "$remote" "$destination"); or return
    for name in $remotes
        test "$namespace" != refs/tags; or continue
        set -a prefixes "refs/remotes/$name"
        set -l cached (__gh_cached_branches "$name" "$destination" $ref_names); or return
        set -a refs (string split -f 1 \t -- $cached)
        set -a revisions (string split -f 2 \t -- $cached)
    end

    set -l requested_path "$(string trim -r -c / -- "$route[2]")"
    for source in cached remote
        if test "$source" = remote
            # gho only needs to check ambiguity among locally known refs.
            test "$cached_only" != true; or return 1
            if test "$namespace" = refs/tags
                set -l cache (__gh_compare_cache "$remote" "$destination"); or return
                for ref in $names
                    set -l revision (__gh_direct_commit "$destination" (__gh_cache_refs "$destination" "$cache" "refs/tags/$ref")); or continue
                    set -l path "$(string split -m 1 -f 2 -- "$ref/" "$requested_path")"
                    printf '%s\n' "$revision" "$revision" "$path" "$revision"
                    return 0
                end
            end
            set -l query_remote "$remote"
            set -q remotes[1]; and set query_remote "$remotes[1]"
            set -q patterns[1]; or break
            set -l advertised (git -C "$destination" ls-remote --refs --heads --tags -- "$query_remote" $patterns); or begin
                if test -z "$namespace"; and string match -qr '^[0-9a-fA-F]{4,39}$' -- "$commit_path[1]"; and __gh_commit "$destination" "$commit_path[1]" >/dev/null
                    printf '%s: cannot disambiguate this hexadecimal ref without remote refs; use a full 40-character commit hash for offline access\n' "$0" >&2
                end
                return 1
            end
            set refs (string split -f 2 \t -- $advertised)
            set revisions (string split -f 1 \t -- $advertised)
            set prefixes $source_prefixes
        end

        for ref in $names
            set -l path "$(string split -m 1 -f 2 -- "$ref/" "$requested_path")"
            for prefix in $prefixes
                set -l index (contains -i -- "$prefix/$ref" $refs)
                if test -n "$index"
                    printf '%s\n' "$prefix/$ref" "$ref" "$path" "$revisions[$index]"
                    return 0
                end
            end
            if test -z "$namespace"; and test "$ref" = HEAD; and test "$cached_only" != true
                set -l revision (__ghe_compare_ref "$remote" "$destination" HEAD cached); or return
                # A cached default can predate the requested path; try one refresh.
                if test -n "$path"; and not git --no-lazy-fetch -C "$destination" rev-parse --verify --quiet "$revision:$path" >/dev/null
                    set -l refreshed (__ghe_compare_ref "$remote" "$destination" HEAD refresh 2>/dev/null)
                    and set revision $refreshed
                end
                printf '%s\n' "$revision" "$revision" "$path" "$revision"
                return 0
            end
            # Check advertised refs before treating a hex name as a commit.
            if test "$source" = remote; and test -z "$namespace"; and string match -qr '^[0-9a-fA-F]{4,39}$' -- "$ref"
                printf '%s\n' "$ref" "$ref" "$path" "$ref"
                return 0
            end
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

function __ghe_tracking_commit --argument-names name destination ref
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
    if not __gh_ref_spelling_safe "$destination" "$tracking_ref"
        printf '%s: tracking ref conflicts with a differently spelled ref: %s\n' "$0" "$tracking_ref" >&2
        return 1
    end
    set -l source_ref (__gh_tracking_source "$name" "$destination" "$tracking_ref" $refspecs)
    if test -n "$source_ref"; and test "$source_ref" != "$branch_ref"
        printf '%s: fetch destination is mapped from another branch or ref: %s -> %s\n' "$0" "$source_ref" "$tracking_ref" >&2
        return 1
    end
    if git -C "$destination" symbolic-ref -q "$tracking_ref" >/dev/null 2>&1
        printf '%s: fetch destination is symbolic: %s\n' "$0" "$tracking_ref" >&2
        return 1
    end
    # Fetch the commit without replacing a local branch or tag.
    if string match -qri '^refs/(heads|tags)/' -- "$tracking_ref"
        __ghe_fetch_head "$destination" --refmap= -- "$name" "$branch_ref"
        return $status
    end
    # A known commit can still be missing its remote-tracking ref.
    set -l commit
    if not __gh_mapped_alias_for "$destination" "$tracking_ref" >/dev/null
        set commit (__gh_commit "$destination" "$tracking_ref")
    end
    if not set -q commit[1]
        set -l fetched (__ghe_fetch "$destination" --verbose --refmap= -- "$name" "+$branch_ref:$tracking_ref"); or return
        set commit (__gh_fetched_oids (string escape --style=regex -- "$tracking_ref") $fetched); or return
    end
    if test "$mapping_status" -ne 0
        # Single-branch clones need a mapping for future fetches, too.
        git -C "$destination" remote set-branches --add -- "$name" "$ref"; or return
    end
    printf '%s\n' "$commit"
end

function __gh_fetched_oids --argument-names targets
    set -q argv[2]; or return 1
    string match -rg "^[ +t*=] [0-9a-f]+ ([0-9a-f]+) $targets\$" -- $argv[2..]
end

function __ghe_fetch --argument-names destination
    # Explicit fetches skip unrelated tags and update their destinations together.
    git -C "$destination" fetch --atomic --porcelain --no-progress --no-tags --no-prune-tags --no-recurse-submodules $argv[2..]
end

function __ghe_fetch_head --argument-names destination
    # FETCH_HEAD is shared with other fetches in this worktree.
    set -l fetched (__ghe_fetch "$destination" $argv[2..]); or return
    __gh_fetched_oids FETCH_HEAD $fetched
end

function __ghe_pull --argument-names destination remote requested_branch requested_path
    set -l changes "$(git -C "$destination" status --porcelain --untracked-files=all)"; or return
    if test -n "$changes"
        printf '%s: checkout has local changes; skipping pull\n' "$0" >&2
        return 0
    end
    set -l branch "$(git -C "$destination" symbolic-ref -q HEAD)"; or return 0
    if test "$branch" != "refs/heads/$requested_branch"
        printf '%s: checkout branch does not match the requested branch: %s\n' "$0" "$requested_branch" >&2
        return 1
    end
    set -l upstream (git -C "$destination" for-each-ref --format='%(upstream:remotename)%0a%(upstream:remoteref)%0a%(upstream)%0a%(objectname)' -- "$branch"); or return
    if contains -- '' "$upstream[1]" "$upstream[2]" "$upstream[3]"
        printf '%s: no upstream configured; skipping pull\n' "$0" >&2
        return 0
    end
    set -l source_ref "refs/heads/$requested_branch"
    if not contains -- "$upstream[2]" "$source_ref" "heads/$requested_branch" "$requested_branch"
        printf '%s: upstream branch does not match the requested branch: %s\n' "$0" "$upstream[2]" >&2
        return 1
    end

    if test "$upstream[1]" != .
        set -l remotes (__gh_remotes "$remote" "$destination"); or return
        if not contains -- "$upstream[1]" $remotes
            printf '%s: upstream remote does not match the requested repository: %s\n' "$0" "$upstream[1]" >&2
            return 1
        end
        # Skip local branches, tags, symbolic refs, and destinations shared by different sources.
        set -l refspecs (__gh_refspecs "$upstream[1]" "$destination")
        set -l sources "$source_ref"
        contains -- "$upstream[2]" $sources; or set -a sources "$upstream[2]"
        for source in $sources
            __gh_tracking_ref "$source" $refspecs >/dev/null
            if test "$status" -eq 2
                printf '%s: upstream is excluded by the remote fetch configuration: %s %s\n' "$0" "$upstream[1]" "$source" >&2
                return 1
            end
        end
        set -l refmap_options
        for spec in $refspecs
            set -l fields (string split -m 1 : -- (string replace -r '^\+' '' -- "$spec"))
            test -n "$fields[2]"; or continue
            set -l target (__gh_map_ref "$fields[1]" "$fields[2]" "$source_ref"); or continue
            __gh_safe_tracking "$destination" "$target"; or continue
            test "$(__gh_tracking_source "$upstream[1]" "$destination" "$target" $refspecs)" = "$source_ref"; or continue
            # A loose ref can shadow a differently cased tracking ref.
            set -l existing (git -C "$destination" for-each-ref --ignore-case --format='%(refname)' -- "$target"); or return
            set -l same_name (string match -i -- "$target" $existing)
            string match -vq -- "$target" $same_name; and continue
            __gh_ref_path_exact "$destination" "$target"; or continue
            set -a refmap_options "--refmap=$spec"
        end
        if not set -q refmap_options[1]
            set refmap_options --refmap=
        end
        set -l merge_ref (__ghe_fetch_head "$destination" $refmap_options -- "$upstream[1]" "$source_ref"); or return
        git -C "$destination" rev-parse --verify --quiet "$merge_ref:$requested_path" >/dev/null; or return 0
        if test "$(git -C "$destination" config --type=bool --get core.sparseCheckout)" = true
            git --literal-pathspecs -C "$destination" ls-tree -rz --full-tree --name-only "$merge_ref" -- "$requested_path" |
                git -C "$destination" sparse-checkout check-rules -z |
                string split0 -q
            or return 0
        end
        set changes "$(git -C "$destination" status --porcelain --untracked-files=all)"; or return
        if test "$upstream[4]" != "$(git -C "$destination" rev-parse --verify HEAD)"
            printf '%s: checkout commit changed while fetching; skipping pull\n' "$0" >&2
            return 1
        end
        if test "$branch" != "$(git -C "$destination" symbolic-ref -q HEAD)"
            printf '%s: checkout branch changed while fetching; skipping pull\n' "$0" >&2
            return 1
        end
        if test -n "$changes"
            printf '%s: checkout has local changes; skipping pull\n' "$0" >&2
            return 0
        end
        git -C "$destination" merge --quiet --ff-only --no-squash --no-autostash --no-overwrite-ignore -- "$merge_ref"
    end
end

function __gh_commit_prefix --argument-names destination prefix
    # Resolve abbreviated object IDs without consulting local ref names.
    set -l fetched $argv[3..]
    set -l matches
    for object in (git --no-lazy-fetch -C "$destination" rev-parse --disambiguate="$prefix")
        set -l commit "$(__gh_commit "$destination" "$object")"
        test -n "$commit"; or continue
        if set -q fetched[1]
            # Resolve fork-qualified prefixes only among the fetched histories.
            set -l outside (printf '^%s\n' $fetched | git --no-lazy-fetch -C "$destination" rev-list --max-count=1 "$commit" --stdin); or return
            test -z "$outside"; or continue
            if test "$object" != "$commit"
                # A local tag may peel to a fetched commit without belonging to the fork.
                set -l fetched_tag (
                    printf '%s\n' $fetched | git --no-lazy-fetch -C "$destination" rev-list --objects --no-object-names --max-count=0 --filter=tree:0 --stdin | string match -- "$object"
                    test "$pipestatus[2]" -eq 0
                ); or return
                test -n "$fetched_tag"; or continue
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
    # Include unchanged tracking destinations in the fetch output.
    set -l fetched (printf '%s\n' $refs | __ghe_fetch "$destination" --verbose --refmap= $options --stdin -- "$remote"); or return
    __gh_fetched_oids '.+' $fetched
end

function __gh_compare_cache --argument-names remote destination
    set -l github (__gh_parse "$remote"); or return
    set -l identity (string lower -- "$github[1]" | git -C "$destination" hash-object --stdin); or return
    printf 'refs/gh/compare/%s\n' "$identity"
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

function __gh_safe_tracking --argument-names destination ref
    string match -q 'refs/*' -- "$ref"; or return 1
    string match -qri '^refs/(heads|tags)/' -- "$ref"; and return 1
    not git -C "$destination" symbolic-ref -q --no-recurse "$ref" >/dev/null 2>&1
end

function __gh_refs_overlap --argument-names ref
    set -q argv[2]; or return 1
    string match -iq -- "$ref" $argv[2..]; and return
    string match -iq -- "$ref/*" $argv[2..]; and return
    set -l parts (string split / -- "$ref")
    while set -q parts[2]
        set -e parts[-1]
        string match -iq -- (string join / -- $parts) $argv[2..]; and return
    end
    return 1
end

function __gh_head_alias_reserved --argument-names destination name
    set -l alias "refs/remotes/$name/HEAD"
    # A future fetch can dereference a symbolic destination and overwrite its target.
    for writer in (git -C "$destination" remote)
        for spec in (__gh_refspecs "$writer" "$destination")
            set spec (string replace -r '^\+' '' -- "$spec")
            if test "$writer" = "$name"; and test "$spec" = "refs/heads/*:refs/remotes/$name/*"
                continue
            end
            set -l target (string split -m 1 -f 2 : -- "$spec")
            test -n "$target"; or continue
            if __gh_refs_overlap "$alias" "$target"; or __gh_source_ref "$alias" "$spec" >/dev/null
                return 0
            end
        end
    end
    return 1
end

function __gh_mapped_alias_for --argument-names destination ref
    # Exact fetch destinations can write through a symref. Wildcard mappings skip them.
    for writer in (git -C "$destination" remote)
        for spec in (__gh_refspecs "$writer" "$destination")
            set -l alias (string split -m 1 -f 2 : -- "$spec")
            test -n "$alias"; and test "$alias" != "$ref"; or continue
            string match -q '*\**' -- "$alias"; and continue
            set -l target "$(git -C "$destination" symbolic-ref -q "$alias" 2>/dev/null)"; or continue
            if test "$target" != "$ref"
                string match -iq -- "$ref" "$target"; or continue
                __gh_ref_paths_distinct "$destination"; and continue
            end
            printf '%s\n' "$alias"
            return 0
        end
    end
    return 1
end

function __gh_head_alias_safe --argument-names destination name
    set -l alias "refs/remotes/$name/HEAD"
    __gh_ref_path_exact "$destination" "$alias"; or return
    __gh_head_alias_reserved "$destination" "$name"; and return 2
    # Packed refs also need case-insensitive hierarchy checks.
    set -l refs (git -C "$destination" for-each-ref \
        --format='%(if)%(symref)%(then)%(else)%(refname)%(end)'); or return
    not __gh_refs_overlap "$alias" $refs
end

function __ghe_cached_default --argument-names destination cache oid
    set -l snapshot "$(__gh_direct_commit "$destination" (__gh_cache_refs "$destination" "$cache" HEAD))"
    set -l observed
    for tracking in $argv[4..]
        set -l tip "$(__gh_commit "$destination" "$tracking")"
        test "$tip" != "$snapshot"; or continue
        if test -n "$snapshot"
            set -l marker "$(__gh_cache_refs "$destination" "$cache/tracking-synced" "$tracking")"; or return
            # An independent snapshot has no reliable observation order.
            test "$(__gh_direct_commit "$destination" "$marker")" = "$snapshot"; or return 0
        end
        # Multiple later observations cannot be ordered, including force pushes.
        if set -q observed[1]; and test "$tip" != "$observed"
            return 0
        end
        set observed "$tip"
    end
    set -q observed[1]; or set observed "$oid"
    printf '%s\n' "$observed"
end

function __gh_default_cache_consistent --argument-names remote destination tracking
    set -l cache (__gh_compare_cache "$remote" "$destination"); or return
    set -l snapshot (__gh_direct_commit "$destination" (__gh_cache_refs "$destination" "$cache" HEAD)); or return 0
    set -l marker (__gh_cache_refs "$destination" "$cache/tracking-synced" "$tracking"); or return
    test "$(__gh_direct_commit "$destination" "$marker")" = "$snapshot"
end

function __gh_snapshot_observations --argument-names destination cache
    for snapshot in $argv[3..]
        set -l oid "$(git --no-lazy-fetch -C "$destination" show-ref --hash --verify "$snapshot" 2>/dev/null)"
        set -l pointer "$cache/tracked/$(path basename -- "$snapshot")"
        set -l tracked "$(git -C "$destination" symbolic-ref -q --no-recurse "$pointer" 2>/dev/null)"
        printf '%s\t%s\t%s\n' "$snapshot" "$oid" "$tracked"
    end
end

function __ghe_compare_ref --argument-names remote destination ref mode
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
    set -l cache (__gh_compare_cache "$remote" "$destination"); or return
    set -l candidates
    set -l tracking_candidates
    set -l tracking_names
    set -l branch_tracking
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
                        test -n "$tracking"; or continue
                        __gh_safe_tracking "$destination" "$tracking"; or continue
                        __gh_ref_spelling_safe "$destination" "$tracking"; or continue
                        __gh_mapped_alias_for "$destination" "$tracking" >/dev/null; and continue
                        set -l tracked_source (__gh_tracking_source "$name" "$destination" "$tracking" $specs)
                        if test "$source" = HEAD
                            if test -n "$tracked_source"; and not string match -q 'refs/heads/*' -- "$tracked_source"
                                continue
                            end
                        else if test "$tracked_source" = "$source"
                            set -a branch_tracking "$tracking"
                        else
                            continue
                        end
                        if test "$mode" = cached; and test -n "$tracked_source"; and __gh_commit "$destination" "$tracking" >/dev/null
                            set -a tracking_names "$name"
                            contains -- "$tracking" $tracking_candidates; or set -a tracking_candidates "$tracking"
                        else
                            set -a candidates "$tracking"
                        end
                    end
                case 'refs/tags/*'
                    test "$qualified" != false; or set -a candidates "$source"
            end
        end
    end
    set -l refresh_default false
    # A refresh request must not fall back to cached commits.
    test "$mode" != refresh; or set refresh_default true
    if test "$mode" = cached; and test "$ref" = HEAD
        # Every matching remote needs a usable cached default before staying offline.
        if not set -q tracking_candidates[1]; or test (count $tracking_names) -ne (count $remotes)
            set refresh_default true
        end
    end
    set -l oid "$(__gh_direct_commit "$destination" $tracking_candidates $candidates)"
    if test "$mode" = cached; and test "$ref" = HEAD; and test "$refresh_default" = false; and test -n "$oid"
        set -l observed (__ghe_cached_default "$destination" "$cache" "$oid" $tracking_candidates); or return
        if set -q observed[1]
            set oid "$observed"
        else
            set refresh_default true
        end
    end
    if test -n "$oid"
        if test "$mode" = cached; and test "$refresh_default" = false
            __gh_commit "$destination" "$oid$ancestry[1]"
            return $status
        else if string match -qr '^[0-9a-fA-F]{40}$' -- "$ref"
            __gh_commit "$destination" "$oid$ancestry[1]"; and return
        end
    else if test "$qualified" = false; and string match -qr '^[0-9a-fA-F]{4,39}$' -- "$ref"
        # Only a prefix without a known named ref is immutable and needs no refresh.
        set oid (__gh_commit_prefix "$destination" "$ref")
        if test -n "$oid"
            __gh_commit "$destination" "$oid$ancestry[1]"; and return
            set ref "$oid"
        end
    end

    # A delayed fetch must not overwrite a newer default observation.
    set -l head_cache
    set -l previous_head
    set -l previous_aliases
    if contains -- HEAD $sources; or string match -q 'refs/heads/*' -- $sources
        set head_cache (__gh_cache_refs "$destination" "$cache" HEAD)[1]; or return
        set previous_head "$(git --no-lazy-fetch -C "$destination" show-ref --hash --verify "$head_cache" 2>/dev/null)"
        for name in $remotes
            set -a previous_aliases "$(git -C "$destination" symbolic-ref -q --no-recurse "refs/remotes/$name/HEAD" 2>/dev/null)"
        end
    end

    # Observe both the requested name and its canonical source before refreshing.
    set -l snapshot_refs (string match -- "$cache/by-ref/*" $candidates | string match -v -- "$head_cache")
    set -l observations (__gh_snapshot_observations "$destination" "$cache" $snapshot_refs)

    set -l fetch_refs "$ref"
    set -l default_source
    set -l default_oid
    set -l fetch_status 0
    if not string match -qr '^[0-9a-fA-F]{40}$' -- "$ref"
        # Status 2 means the remote answered but the requested name is absent.
        set -l advertised (git -C "$destination" ls-remote --symref --exit-code -- "$query" $sources)
        set fetch_status "$status"
        if contains -- "$fetch_status" 0 2
            if test "$ref" = HEAD
                set default_source (__gh_advertised_head $advertised)
                set default_oid (string match -rg '^([0-9a-f]+)\tHEAD$' -- $advertised)
            end
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
    if test -n "$default_source"
        set -l default_branch (string replace -r '^refs/heads/' '' -- "$default_source")
        set -l default_snapshots
        for name in "$default_source" "$default_branch"
            set -l snapshot (__gh_cache_refs "$destination" "$cache" "$name")[1]; or return
            contains -- "$snapshot" "$head_cache" $snapshot_refs; or set -a default_snapshots "$snapshot"
        end
        set -a snapshot_refs $default_snapshots
        set -a observations (__gh_snapshot_observations "$destination" "$cache" $default_snapshots)
    end

    set -l fetch_tracking
    set -l default_tracking
    set -l default_names
    set -l invalidate_default false
    test "$ref" != HEAD; or set invalidate_default true
    set -l source "$fetch_refs[1]"
    test -z "$default_source"; or set source "$default_source"
    if set -q remotes[1]; and string match -q 'refs/heads/*' -- "$source"
        set -l names "$query"
        test "$ref" != HEAD; or set names $remotes
        for name in $names
            set -l specs (__gh_refspecs "$name" "$destination")
            set -l tracking (__gh_tracking_ref "$source" $specs); or continue
            test "$(__gh_tracking_source "$name" "$destination" "$tracking" $specs)" = "$source"; or continue
            __gh_safe_tracking "$destination" "$tracking"; or continue
            __gh_ref_spelling_safe "$destination" "$tracking"; or continue
            contains -- "$tracking" $fetch_tracking; or set -a fetch_tracking "$tracking"
            if test "$ref" = HEAD
                set -a default_tracking "$tracking"
                set -a default_names "$name"
            end
        end
    end
    set -l fetch_specs $fetch_refs
    if set -q fetch_tracking[1]
        # Remote-tracking refs follow force pushes, like the default fetch refspec.
        set fetch_specs "+$source:"$fetch_tracking
    end
    set -l fetched
    if test "$fetch_status" -eq 0
        set fetched (__ghe_fetch_history "$destination" "$query" $fetch_specs)
        set fetch_status "$status"
        if test "$fetch_status" -ne 0; and set -q fetch_tracking[1]
            # A stale ref hierarchy or lock must not prevent a read-only comparison.
            set -l specs (__gh_refspecs "$query" "$destination")
            if contains -- "$(__gh_default_ref "$query" "$destination" $specs)" $fetch_tracking
                set invalidate_default true
            end
            set fetch_tracking
            set default_tracking
            set default_names
            set fetched (__ghe_fetch_history "$destination" "$query" $fetch_refs)
            set fetch_status "$status"
        end
    end
    if test "$fetch_status" -ne 0
        if test "$refresh_default" = true
            printf '%s: cannot refresh default HEAD; refusing to use ambiguous cached refs\n' "$0" >&2
            return 1
        end
        test -n "$oid"; or return "$fetch_status"
        if set -q branch_tracking[1]
            # A snapshot synchronized with a tracking ref can follow later ordinary fetches.
            set -l snapshot_ref "$candidates[1]"
            set -l snapshot (__gh_direct_commit "$destination" "$snapshot_ref")
            if not set -q snapshot[1]; and test "$ref" != "$sources[1]"
                set snapshot_ref "$candidates[2]"
                set snapshot (__gh_direct_commit "$destination" "$snapshot_ref")
            end
            if set -q snapshot[1]; and test "$snapshot" = "$oid"
                set -l pointer "$cache/tracked/$(path basename -- "$snapshot_ref")"
                set -l tracking "$(git -C "$destination" symbolic-ref -q --no-recurse "$pointer" 2>/dev/null)"
                if contains -- "$tracking" $branch_tracking
                    and set -l observed (__gh_direct_commit "$destination" "$tracking")
                    set oid "$observed"
                end
            end
        end
        if __gh_commit "$destination" "$oid$ancestry[1]"
            printf '%s: could not refresh comparison ref; using cached commit: %s\n' "$0" "$ref" >&2
            return 0
        end
        printf '%s: could not fetch the history for comparison ref: %s\n' "$0" "$ref$ancestry[1]" >&2
        return 1
    end

    if not set -q fetch_refs[1]
        if test "$qualified" = true
            set oid (__gh_commit_prefix "$destination" "$ref" $fetched)
        else
            set oid (__gh_commit_prefix "$destination" "$ref")
        end
    else
        set oid (__gh_commit "$destination" "$fetched[1]")
    end
    if test -z "$oid"
        printf '%s: comparison commit is missing or ambiguous: %s\n' "$0" "$ref" >&2
        return 1
    end
    # Cross-remote alias collisions cannot represent every synchronized default.
    for name in $default_names
        set -l index (contains -i -- "$name" $default_names)
        set -l head_alias "refs/remotes/$name/HEAD"
        set -l other_tracking (string match -v -- "$default_tracking[$index]" $fetch_tracking)
        if __gh_refs_overlap "$head_alias" $other_tracking
            set default_names
            break
        end
    end
    set -l updates
    for tracking in $fetch_tracking
        set -a updates "verify $tracking $oid"
    end
    set -l alias_updates
    if test "$invalidate_default" = true; and set -q remotes[1]
        set -l markers (git -C "$destination" for-each-ref --format='%(refname)' -- "$cache/tracking-synced/"); or return
        set -l kept_markers
        for name in $remotes
            set -l head_alias "refs/remotes/$name/HEAD"
            set -l remote_index (contains -i -- "$name" $remotes)
            set -l previous_alias "$previous_aliases[$remote_index]"
            set -l index (contains -i -- "$name" $default_names)
            if test -n "$index"
                set -l tracking "$default_tracking[$index]"
                __gh_head_alias_safe "$destination" "$name"
                switch "$status"
                    case 0
                        if test -n "$previous_alias"
                            set -a alias_updates "symref-update $head_alias $tracking ref $previous_alias"
                        else
                            set -a alias_updates "symref-create $head_alias $tracking"
                        end
                    case 2
                        if test -n "$previous_alias"
                            set -a updates "symref-delete $head_alias $previous_alias"
                        end
                end
                set -l marker "$(__gh_cache_refs "$destination" "$cache/tracking-synced" "$tracking")"; or return
                if not contains -- "$marker" $kept_markers
                    set -a kept_markers "$marker"
                    set -a updates "update $marker $oid"
                end
            else if test -n "$previous_alias"; and __gh_ref_path_exact "$destination" "$head_alias"
                set -a updates "symref-delete $head_alias $previous_alias"
            end
        end
        for marker in $markers
            contains -- "$marker" $kept_markers; or set -a updates "delete $marker"
        end
    end
    if set -q fetch_refs[1]
        set -l cache_sources "$ref"
        contains -- "$fetch_refs[1]" $cache_sources; or set -a cache_sources "$fetch_refs[1]"
        if test "$invalidate_default" = true
            contains -- HEAD $cache_sources; or set -a cache_sources HEAD
        end
        if test -n "$default_source"
            # Without an explicit branch fetch, HEAD may have changed since advertisement.
            if set -q fetch_tracking[1]; or test "$fetched[1]" = "$default_oid"
                set -a cache_sources "$default_source" (string replace -r '^refs/heads/' '' -- "$default_source")
            end
        end
        set -l branch_source "$source"
        set -l branch_name (string replace -r '^refs/heads/' '' -- "$branch_source")
        set -l absent (string replace -ar . 0 -- "$oid")
        for source in $cache_sources
            set -l cache_refs (__gh_cache_refs "$destination" "$cache" "$source"); or return
            set -l snapshot "$cache_refs[1]"
            set -l observed (string split -m 2 \t -- (string match -r -- "^$snapshot\t.*\$" $observations))
            set -l update "update $snapshot $oid"
            if test "$source" = HEAD
                set -l expected "$previous_head"
                test -n "$expected"; or set expected "$absent"
                set update "$update $expected"
            else if set -q observed[1]
                set -l expected "$observed[2]"
                test -n "$expected"; or set expected "$absent"
                set update "$update $expected"
            end
            contains -- "$update" $updates; and continue
            if not set -q observed[1]; or string match -q 'refs/tags/*' -- "$source"
                set -a updates "$update"
                continue
            end

            # The selected source can change even when the old and new commits are equal.
            set -l pointer "$cache/tracked/$(path basename -- "$snapshot")"
            set -l previous "$observed[3]"
            if set -q fetch_tracking[1]; and contains -- "$source" "$branch_source" "$branch_name"
                if test -n "$previous"
                    set -a updates "$update" "symref-update $pointer $fetch_tracking[1] ref $previous"
                else
                    set -a updates "$update" "symref-create $pointer $fetch_tracking[1]"
                end
            else if test -n "$previous"
                set -a updates "symref-delete $pointer $previous" "$update"
            else
                set -a updates "verify $pointer $absent" "$update"
            end
        end
        # Publish equivalent snapshots and default metadata in one transaction.
        set -l diagnostic "$(printf '%s\n' $updates $alias_updates | git -C "$destination" update-ref --no-deref --stdin 2>&1)"
        set -l cache_status "$status"
        if test "$cache_status" -ne 0; and test "$invalidate_default" = true
            set -l changed false
            if test "$previous_head" != "$(git --no-lazy-fetch -C "$destination" show-ref --hash --verify "$head_cache" 2>/dev/null)"
                or test "$(string join \n -- $observations)" != "$(__gh_snapshot_observations "$destination" "$cache" $snapshot_refs)"
                set changed true
            end
            for tracking in $fetch_tracking
                test "$(__gh_commit "$destination" "$tracking")" = "$oid"; or set changed true
            end
            for name in $remotes
                set -l remote_index (contains -i -- "$name" $remotes)
                set -l alias "$(git -C "$destination" symbolic-ref -q --no-recurse "refs/remotes/$name/HEAD" 2>/dev/null)"
                test "$alias" = "$previous_aliases[$remote_index]"; or set changed true
            end
            if test "$changed" = false
                if set -q alias_updates[1]
                    # A dangling symref or lock may block an optional alias.
                    set diagnostic "$(printf '%s\n' $updates | git -C "$destination" update-ref --no-deref --stdin 2>&1)"
                    set cache_status "$status"
                end
                if test "$cache_status" -ne 0
                    printf '%s\n' "$diagnostic" >&2
                    return "$cache_status"
                end
            end
        end
    end
    __gh_commit "$destination" "$oid$ancestry[1]"; and return
    printf '%s: no commit matches comparison ref: %s\n' "$0" "$ref$ancestry[1]" >&2
    return 1
end

function __ghe_merge_base --argument-names destination base head shallow
    set -l merge_base "$(git --no-lazy-fetch -C "$destination" merge-base "$base" "$head" 2>/dev/null)"; or return 1
    if test -s "$shallow"; and not contains -- "$merge_base" "$base" "$head"
        # A shallow boundary outside the known base's ancestry can hide a closer common commit.
        git --no-lazy-fetch -C "$destination" rev-list "$base" "$head" "^$merge_base" | command grep -Fxf "$shallow" >/dev/null
        set -l checks $pipestatus
        test "$checks[1]" -eq 0; and test "$checks[2]" -eq 1; or return 2
    end
    printf '%s\n' "$merge_base"
end

function __ghe_compare --argument-names remote destination comparison
    test -n "$comparison"; or return 0
    set -l range
    set -l dots ...
    switch "$comparison"
        case '*...*'
            set range (string split -m 1 ... -- "$comparison")
        case '*..*'
            set range (string split -m 1 .. -- "$comparison")
            set dots ..
        case '*'
            set range HEAD "$comparison"
    end
    test -n "$range[1]"; or set range[1] HEAD
    test -n "$range[2]"; or set range[2] HEAD
    set -l base (__ghe_compare_ref "$remote" "$destination" "$range[1]"); or return
    set -l head (__ghe_compare_ref "$remote" "$destination" "$range[2]"); or return
    if test "$dots" = ..
        git -C "$destination" diff "$base" "$head" --
        return
    end

    set -l shallow "$(git -C "$destination" rev-parse --path-format=absolute --git-path shallow)"; or return
    set -l merge_base (__ghe_merge_base "$destination" "$base" "$head" "$shallow")
    set -l merge_status "$status"
    if test "$merge_status" -ne 0; and test -s "$shallow"
        and test (count (string match -r '^[0-9a-fA-F]{4,40}(?:[~^][0-9]*)*$' -- $range)) -eq 2
        and set -l name (__ghe_remote "$remote" "$destination")
        and __ghe_fetch_history "$destination" "$name" "$base" "$head" >/dev/null
        set merge_base (__ghe_merge_base "$destination" "$base" "$head" "$shallow")
        set merge_status "$status"
    end
    if test "$merge_status" -eq 2
        printf '%s: shallow history may hide a closer comparison merge base; fetch more history or use a two-dot comparison\n' "$0" >&2
        return 1
    end
    if test -z "$merge_base"
        printf '%s: comparison has no local merge base; fetch more history or use a two-dot comparison\n' "$0" >&2
        return 1
    end
    git -C "$destination" diff "$base...$head" --
end

function __ghe_url_route --argument-names repository tail
    switch "$tail"
        case 'tag/*' 'branch/*' 'oid/*' raw/refs/heads/ raw/refs/tags/
            # Internal routes and bare namespaces do not identify GitHub refs.
            return 0
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
            set -l ref (string match -rg '^archive/(.*)\.(?:zip|tar\.gz)$' -- "$tail"); or return 0
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
        case '*'
            printf '%s\n' "$tail"
    end
end

function __gh_publish_snapshot --argument-names destination ref object previous
    test -n "$ref"; or return 0
    git -C "$destination" update-ref --no-deref "$ref" "$object" "$previous" >/dev/null 2>&1
    return 0
end

function __ghe_pull_request --argument-names remote destination number
    string match -qr '^[1-9][0-9]*$' -- "$number"; or return 1
    set -l name (__ghe_remote "$remote" "$destination"); or return
    # Remote names can change or be reused for another repository.
    set -l github (__gh_parse "$remote"); or return
    set -l identity (string lower -- "$github[1]" | git -C "$destination" hash-object --stdin); or return
    set -l cache "refs/gh/pull/$identity/$number/head"
    set -l previous "$(git -C "$destination" show-ref --hash --verify "$cache" 2>/dev/null)"
    # Pull requests move, so refresh the head before falling back to the cache.
    if set -l object (__ghe_fetch_head "$destination" --refmap= -- "$name" "refs/pull/$number/head")
        set -l revision (__gh_commit "$destination" "$object"); or return
        # A later fetch may already have published a different head.
        __gh_publish_snapshot "$destination" "$cache" "$revision" "$previous"
        printf '%s\n' "$revision"
        return
    end
    __gh_direct_commit "$destination" "$cache"
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
    if not set -q editor[1]
        printf '%s: EDITOR is empty\n' "$0" >&2
        return 1
    end
    if test -n "$end_line"
        set -l selection V
        if test -n "$column$end_column"
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
    set -l tag_object
    set -l tag_cache
    set -l previous_tag
    if string match -q 'refs/tags/*' -- "$full_ref"
        and string match -qr '^[0-9a-fA-F]{40}$' -- "$revision"
        and set -l cache (__gh_compare_cache "$remote" "$destination")
        and set -l refs (__gh_cache_refs "$destination" "$cache" "$full_ref")
        set tag_object "$revision"
        set tag_cache "$refs[1]"
        set previous_tag "$(git -C "$destination" show-ref --hash --verify "$tag_cache" 2>/dev/null)"
    end

    if string match -qr '^[0-9a-fA-F]{4,40}$' -- "$full_ref"
        set revision (__gh_commit_prefix "$destination" "$full_ref")
    else
        set revision "$(__gh_commit "$destination" "$revision")"
    end
    set -l current_branch "$(git -C "$destination" symbolic-ref -q HEAD)"
    set -l branch_ref ''
    if string match -qr '^refs/(heads|remotes)/' -- "$full_ref"
        set branch_ref "refs/heads/$ref"
        if not __gh_ref_spelling_safe "$destination" "$branch_ref"
            printf '%s: local branch conflicts with a differently spelled ref: %s\n' "$0" "$branch_ref" >&2
            return 1
        end
        if git -C "$destination" symbolic-ref -q "$branch_ref" >/dev/null 2>&1
            printf '%s: local branch is symbolic: %s\n' "$0" "$branch_ref" >&2
            return 1
        end
        if test "$current_branch" = "$branch_ref"; and test "$full_ref" = "$branch_ref"; and test -n "$revision"
            return 0
        end
    else if test -z "$current_branch"; and test -n "$revision"
        if test "$revision" = "$(git -C "$destination" rev-parse HEAD)"
            __gh_publish_snapshot "$destination" "$tag_cache" "$tag_object" "$previous_tag"
            return 0
        end
    end

    set -l changes "$(git -C "$destination" status --porcelain --untracked-files=all)"; or return
    if test -n "$changes"
        printf '%s: keeping the current ref because the checkout has local changes\n' "$0" >&2
        return 0
    end
    set -l current_oid "$(git -C "$destination" rev-parse --verify --quiet HEAD)"
    set -l switch_args
    set -l name
    set -l fetch_remote
    if test -n "$branch_ref"
        set switch_args -- "$ref"
        if not git -C "$destination" show-ref --verify --quiet "$branch_ref"
            set name (__ghe_remote "$remote" "$destination" "$ref" "$full_ref"); or return
            set -l commit (__ghe_tracking_commit "$name" "$destination" "$ref"); or return
            set switch_args --no-track --create "$ref" "$commit^{commit}"
        end
    else
        # Cached tags and commits need no refresh.
        if test -z "$revision"
            set fetch_remote (__ghe_remote "$remote" "$destination"); or return
            if string match -qr '^[0-9a-fA-F]{4,39}$' -- "$full_ref"
                __ghe_fetch_history "$destination" "$fetch_remote" >/dev/null; or return
                set revision (__gh_commit_prefix "$destination" "$full_ref")
                if test -z "$revision"
                    printf '%s: commit %s is missing or ambiguous after fetching remote refs; use a longer or full commit hash\n' "$0" "$ref" >&2
                    return 1
                end
            else
                set revision (__ghe_fetch_head "$destination" --refmap= -- "$fetch_remote" "$full_ref"); or return
                set tag_object "$revision"
            end
        end
        # A commit expression prevents choosing a branch named after the OID.
        set switch_args --detach "$revision^{commit}"
    end
    if test -n "$name$fetch_remote"
        set changes "$(git -C "$destination" status --porcelain --untracked-files=all)"; or return
        if test "$current_branch" != "$(git -C "$destination" symbolic-ref -q HEAD)"
            or test "$current_oid" != "$(git -C "$destination" rev-parse --verify --quiet HEAD)"
            printf '%s: checkout changed while fetching; skipping switch\n' "$0" >&2
            return 1
        end
        if test -n "$changes"
            printf '%s: keeping the current ref because the checkout has local changes\n' "$0" >&2
            return 0
        end
    end
    git -C "$destination" switch --quiet --no-overwrite-ignore $switch_args; or return
    __gh_publish_snapshot "$destination" "$tag_cache" "$tag_object" "$previous_tag"
    if test -n "$name"
        git -C "$destination" config --replace-all "branch.$ref.remote" "$name"; or return
        git -C "$destination" config --replace-all "branch.$ref.merge" "$branch_ref"; or return
    end
end

function __ghe_checkout --argument-names remote destination tail line column end_line end_column
    if string match -qri '^(?:blob|tree|blame|commits?|raw|edit)/.+/\.git(?:/|$)' -- "$tail"
        printf '%s: URL paths cannot address Git metadata\n' "$0" >&2
        return 1
    end
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
    if not __gh_is_ref_route "$tail"
        cd -- "$destination"
        return
    end

    set -l resolved (__gh_resolve "$remote" "$tail" "$destination")
    test (count $resolved) -eq 4; or return 1
    __ghe_switch "$remote" "$destination" "$resolved[1]" "$resolved[2]" "$resolved[4]"; or return

    set -l requested_path "$resolved[3]"
    if test -z "$requested_path"
        cd -- "$destination"
        return
    end
    set -l target "$destination/$requested_path"
    if not test -e "$target"; and not test -L "$target"
        # Pull cannot restore a tracked path omitted from the worktree.
        if string match -qr '^refs/(heads|remotes)/' -- "$resolved[1]"
            and not git --no-lazy-fetch -C "$destination" rev-parse --verify --quiet "HEAD:$requested_path" >/dev/null
            __ghe_pull "$destination" "$remote" "$resolved[2]" "$requested_path"; or return
        end
        if not test -e "$target"; and not test -L "$target"
            printf '%s: path does not exist in this checkout: %s\n' "$0" "$requested_path" >&2
            return 1
        end
    end
    # A Git tree can contain a symlink, but has no entries beneath one.
    set -l components (string split / -- "$requested_path")
    set -e components[-1]
    set -l parent "$destination"
    for component in $components
        set parent "$parent/$component"
        if test -L "$parent"
            printf '%s: path traverses a symlink: %s\n' "$0" "$requested_path" >&2
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
    set -l source_ref
    set -l ref
    set -l commit
    set -l branch "$(git -C "$dir" symbolic-ref -q HEAD)"
    if test -n "$branch"
        set -l upstream (git -C "$dir" for-each-ref --format='%(upstream:remotename)%0a%(upstream:remoteref)%0a%(upstream)' -- "$branch")
        if test -n "$upstream[1]"; and test "$upstream[1]" != .
            set remote "$upstream[1]"
            set remote_ref "$upstream[3]"
            set source_ref "$upstream[2]"
            if test -n "$remote_ref"; and string match -q 'refs/heads/*' -- "$source_ref"
                set ref (string replace -r '\Arefs/heads/' '' -- "$source_ref")
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
            set source_ref "refs/heads/$ref"
            set remote_ref (__gh_tracking_ref "$source_ref" $refspecs)
            test -n "$remote_ref"; or set remote_ref "refs/remotes/$remote/$ref"
        end
        if test -n "$source_ref"
            set -l tracked_source (__gh_tracking_source "$remote" "$dir" "$remote_ref" $refspecs)
            set -l source_status "$status"
            if set -l alias (__gh_mapped_alias_for "$dir" "$remote_ref")
                set tracked_source "mapped symbolic ref $alias"
                set source_status 2
            end
            if test -n "$tracked_source"; and test "$tracked_source" != "$source_ref"
                # A branch page can be opened without trusting the shared tracking ref.
                if test "$source_status" -eq 2; and test -n "$ref"; and test -z "$repo_path"
                    set -l advertised (git -C "$dir" ls-remote --refs -- "$remote" "$source_ref" "refs/tags/$ref" 2>/dev/null)
                    set -l revision (string match -rg "^([0-9a-f]+)\t$(string escape --style=regex -- "$source_ref")\$" -- $advertised)
                    if set -q revision[1]
                        if test (count $advertised) -ne 1
                            or string match -qr '^(?:[0-9a-fA-F]{40}$|refs/(?:heads|tags)/)' -- "$ref"
                            set ref "$revision"
                        end
                        printf '%s/tree/%s\n' "$url" (string escape --style=url -- "$ref")
                        return 0
                    end
                end
                printf '%s: cached remote branch is mapped from another branch or ref: %s -> %s\n' "$0" "$tracked_source" "$remote_ref" >&2
                return 1
            end
        end
        if not __gh_ref_spelling_safe "$dir" "$remote_ref"
            printf '%s: cached remote branch conflicts with a differently spelled ref: %s\n' "$0" "$remote_ref" >&2
            return 1
        end
        if not __gh_safe_tracking "$dir" "$remote_ref"
            printf '%s: fetch destination is not a dedicated tracking ref: %s\n' "$0" "$remote_ref" >&2
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
        set -l record (
            git -C "$dir" --literal-pathspecs ls-tree -z --full-tree "$commit" -- "$repo_path" | string split0
            test "$pipestatus[1]" -eq 0
        ); or return
        set -l fields (string split -m 1 \t -- "$record")
        set kind (string split -f 2 " " -- "$fields[1]")
        if test -z "$kind"
            if test -n "$branch"
                printf '%s: path is not in the cached remote branch; push or fetch first: %s\n' "$0" "$target" >&2
            else
                printf '%s: path is not in the current commit: %s\n' "$0" "$target" >&2
            end
            return 1
        end
        if not contains -- "$kind" tree blob
            printf '%s: unsupported Git object at path: %s\n' "$0" "$target" >&2
            return 1
        end
        set repo_path "$fields[2]"
    end

    # The default-branch homepage needs no ref; other ambiguous links use the commit.
    set -l default_ref "$(__gh_default_ref "$remote" "$dir" $refspecs)"
    if test -z "$repo_path"; and test -n "$branch"; and test "$default_ref" = "$remote_ref"
        # A successful comparison may have learned a new default without updating this alias.
        __gh_default_cache_consistent "$remote_url" "$dir" "$default_ref"; or set default_ref ''
    else if test -z "$default_ref$repo_path"; and test -n "$branch"
        # set-head assumes refs/remotes; cache the advertised HEAD using its mapping.
        set -l source (__gh_advertised_head (git -C "$dir" ls-remote --symref -- "$remote" HEAD 2>/dev/null))
        if set -q source[1]
            set default_ref (__gh_tracking_ref "$source" $refspecs)
            test -n "$default_ref"; or set default_ref "refs/remotes/$remote/$(string replace -r '^refs/heads/' '' -- "$source")"
            set -l tracked_source (__gh_tracking_source "$remote" "$dir" "$default_ref" $refspecs)
            if test -n "$tracked_source"; and test "$tracked_source" != "$source"
                set default_ref ''
            else if __gh_safe_tracking "$dir" "$default_ref"
                and __gh_ref_spelling_safe "$dir" "$default_ref"
                and __gh_head_alias_safe "$dir" "$remote"
                git -C "$dir" symbolic-ref "refs/remotes/$remote/HEAD" "$default_ref" >/dev/null 2>&1
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
