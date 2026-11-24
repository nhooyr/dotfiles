source "$(status dirname)/../github.fish"; or return

function gho --description 'Open a GitHub repository, path, revision, or issue'
    set -l usage 'Usage: gho [--copy] [PATH | REVISION | \'#NUMBER\' | OWNER/REPO | GITHUB_URL]

Print the GitHub URL and open it in the default browser.
Build URLs from local information; never check or fetch the remote.

  gho                              Open the current directory on its branch.
  gho PATH                         Open a local file or directory on its branch.
  gho SYMLINK                      Open the tracked link, or its source checkout.
  gho COMMIT                       Open a locally resolved commit, e.g. HEAD~1.
  gho BRANCH_OR_TAG                Open a local branch, remote-tracking branch, or tag.
  gho \'#2321\'                      Open issue or PR 2321 via /issues/2321.
  gho OWNER/REPO                   Open the repository homepage.
  gho GITHUB_URL                   Open any GitHub page, preserving query/fragment.
  gho SSH_REPOSITORY_URL           Open the corresponding GitHub homepage.
  gho --copy [TARGET]              Print and copy the URL without opening it.
  gho -h, --help                   Show this help.

Existing paths, including deleted tracked files, take priority over revisions.
Use refs/heads/NAME or refs/tags/NAME to select a revision with a conflicting name.
Quote issue numbers so the shell does not treat # as a comment; ./#2321 selects a file.
Branches and tags open tree views; commit IDs and expressions open commit pages.
Resolve revisions locally without fetching missing objects or calling the GitHub API.
Issue and PR numbers always use /issues/NUMBER; GitHub redirects PRs.

Local paths use the configured upstream branch, otherwise the local branch.
The cached default branch opens its homepage; detached HEAD uses its commit.
If the default branch is unknown, main/master also open the homepage.
Unpublished branches and files are opened without checking whether they exist.'
    0="$(status current-function)" usage="$usage" __gho $argv
end

function __gho_url --argument-names target
    # Build links from local metadata only; never inspect or fetch remote content.
    set -l issue $(string match -rg '^#([0-9]+)$' -- "$target")
    set -l revision
    set -l revision_name
    set -q issue[1]; and set target .
    set -l parent "$(path dirname -- "$target")"
    set -l name "$(path basename -- "$target")"
    set -l entry "$parent/$name"
    if not test -e "$target"; and not test -L "$entry"
        # Deleted files may have missing parent directories too.
        set -l base "$parent"
        set -l relative "$name"
        set -l tracked
        if not string match -qr '^(https?://|ssh://|git@)' -- "$target"
            while not test -d "$base"
                set relative "$(path basename -- "$base")/$relative"
                set base "$(path dirname -- "$base")"
            end
            set tracked $(git -C "$base" --literal-pathspecs ls-files -z -- "$relative" 2>/dev/null | string split0)
        end
        if test "$(count $tracked)" -eq 1; and test "$tracked[1]" = "$relative"
            set parent "$base"
            set name "$relative"
            set entry "$parent/$name"
        else
            if not string match -qr '^(https?://|ssh://|git@)' -- "$target"
                set revision "$(git --no-lazy-fetch rev-parse --verify --quiet --end-of-options "$target^{commit}" 2>/dev/null)"
            end
            if test -n "$revision"
                if not contains -- "$target" HEAD @
                    set revision_name "$(git --no-lazy-fetch rev-parse --symbolic-full-name --verify --quiet --end-of-options "$target" 2>/dev/null)"
                end
            else
                set -l github $(__gh_parse "$target"); or return
                set -l url "https://$github[4]/$github[1]"
                if test -n "$github[2]"
                    set url "$url/$(string escape --style=url -- "$github[2]")"
                end
                printf '%s%s\n' "$url" "$(string match -r '[?#].*$' -- "$target")"
                return
            end
        end
    end

    set -l dir "$target"
    set -l kind tree
    if test -n "$revision"
        set dir .
    else if test -L "$entry"; or not test -d "$target"
        set dir "$parent"
        set kind blob
    end
    set -l repo_path "$(git -C "$dir" rev-parse --show-prefix 2>/dev/null)"; or begin
        # Installed dotfile links may live outside their source repository.
        if test -L "$entry"; and test -e "$entry"
            set -l resolved "$(path resolve -- "$entry")"; or return
            __gho_url "$resolved"
            return
        end
        printf '%s: path is not in a Git checkout: %s\n' "$0" "$target" >&2
        return 1
    end
    if test "$kind" = blob
        if test -e "$entry"; and not test -L "$entry"
            set name "$(path basename -- "$(path resolve -- "$entry")")"
        end
        set repo_path "$repo_path$name"
        # Preserve the index's spelling on filesystems that normalize Unicode.
        set -l indexed $(git -C "$dir" --literal-pathspecs ls-files -z --full-name -- "$name" | string split0)
        if test "$(count $indexed)" -eq 1
            set repo_path "$indexed[1]"
        end
    else
        set repo_path "$(string trim -r -c / -- "$repo_path")"
    end

    set -l branch "$(git -C "$dir" symbolic-ref --quiet HEAD 2>/dev/null)"
    if string match -q 'refs/heads/*' -- "$revision_name"
        set branch "$revision_name"
    end
    set -l ref $(string replace -r '^refs/heads/' '' -- "$branch")
    set -l remote
    set -l upstream
    set -l remotes
    set -l config $(git -C "$dir" config --null --get-regexp '^(branch\..*\.(remote|merge)|remote\..*\.url)$' | string split0)
    for record in $config
        set -l fields $(string split -m 1 \n -- "$record")
        if test "$fields[1]" = "branch.$ref.remote"
            set remote "$fields[2]"
        else if test "$fields[1]" = "branch.$ref.merge"; and not set -q upstream[1]
            set upstream $(string replace -r '^refs/heads/' '' -- "$fields[2]")
        end
        set -l remote_name $(string match -rg '^remote\.(.+)\.url$' -- "$fields[1]")
        if set -q remote_name[1]; and not contains -- "$remote_name" $remotes
            set -a remotes "$remote_name"
        end
    end
    set -l revision_remote
    set -l revision_branch
    if string match -q 'refs/remotes/*' -- "$revision_name"
        for name in $remotes
            set -l prefix "refs/remotes/$name/"
            if string match -q "$prefix*" -- "$revision_name"
                and test "$(string length -- "$name")" -gt "$(string length -- "$revision_remote")"
                set revision_remote "$name"
                set revision_branch "$(string replace -- "$prefix" '' "$revision_name")"
            end
        end
    end
    if test -n "$revision_remote"
        set remote "$revision_remote"
        set ref "$revision_branch"
    else if test -n "$remote"; and test "$remote" != .
        if set -q upstream[1]
            set ref "$upstream"
        end
    else if contains -- origin $remotes
        set remote origin
    else if test "$(count $remotes)" -eq 1
        set remote "$remotes[1]"
    else
        printf '%s: set a tracking remote or add an origin remote\n' "$0" >&2
        return 1
    end
    set -l remote_url "$(git -C "$dir" remote get-url -- "$remote")"; or return
    set -l github $(__gh_parse "$remote_url"); or return
    set -l url "https://$github[4]/$github[1]"

    if set -q issue[1]
        printf '%s/issues/%s\n' "$url" "$issue"
        return
    end
    if test -n "$revision"
        set -l target_ref "$revision"
        set kind commit
        switch "$revision_name"
            case 'refs/heads/*'
                set kind tree
                set target_ref "$ref"
            case 'refs/tags/*'
                set kind tree
                set target_ref "$(string replace -- refs/tags/ '' "$revision_name")"
            case 'refs/remotes/*'
                if test -n "$revision_remote"
                    set kind tree
                    set target_ref "$revision_branch"
                end
        end
        printf '%s/%s/%s\n' "$url" "$kind" "$(string escape --style=url -- "$target_ref")"
        return
    end
    if test -z "$branch"
        set ref "$(git -C "$dir" rev-parse HEAD 2>/dev/null)"; or return
    else if test -z "$repo_path"
        # Use the cached default name, or assume main/master when it is missing.
        set -l default "$(git -C "$dir" symbolic-ref --quiet "refs/remotes/$remote/HEAD" 2>/dev/null)"
        if test -z "$default"; and contains -- "$ref" main master
            set default "refs/remotes/$remote/$ref"
        end
        if test "$default" = "refs/remotes/$remote/$ref"
            printf '%s\n' "$url"
            return
        end
    end
    set -l web_path "$ref"
    if test -n "$repo_path"
        set web_path "$web_path/$repo_path"
    end
    printf '%s/%s/%s\n' "$url" "$kind" $(string escape --style=url -- "$web_path")
end

function __gho
    argparse --name "$0" --max-args 1 h/help copy -- $argv; or return
    if set -q _flag_help
        printf '%s\n' "$usage"
        return 0
    end
    if string match -qr '[[:cntrl:]]' -- "$GH_HOST"
        printf '%s: invalid GitHub hostname\n' "$0" >&2
        return 1
    end
    set -l target "$PWD"
    set -q argv[1]; and set target "$argv[1]"
    set -l url "$(__gho_url "$target")"; or return
    if set -q _flag_copy
        printf '%s\n' "$url" | pbc
    else
        printf '%s\n' "$url"
        open "$url"
    end
end
