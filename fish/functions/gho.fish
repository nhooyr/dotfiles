source "$(status dirname)/../github.fish"; or return

function gho --description 'Open the GitHub page for a repository or path'
    set -l usage 'Usage: gho [PATH | OWNER/REPO | GITHUB_URL]

Print the GitHub URL and open it in the default browser.
Build URLs from local information; never check or fetch the remote.

  gho                              Open the current directory on its branch.
  gho PATH                         Open a local file or directory on its branch.
  gho SYMLINK                      Open the tracked link, or its source checkout.
  gho OWNER/REPO                   Open the repository homepage.
  gho GITHUB_URL                   Open any GitHub page, preserving query/fragment.
  gho SSH_REPOSITORY_URL           Open the corresponding GitHub homepage.
  gho -h, --help                   Show this help.

Local paths use the configured upstream branch, otherwise the local branch.
The cached default branch opens its homepage; detached HEAD uses its commit.
If the default branch is unknown, main/master also open the homepage.
Unpublished branches and files are opened without checking whether they exist.'
    0="$(status current-function)" usage="$usage" __gho $argv
end

function __gho_url --argument-names target
    # Build links from local metadata only; never inspect or fetch remote content.
    set -l parent "$(path dirname -- "$target")"
    set -l name "$(path basename -- "$target")"
    set -l entry "$parent/$name"
    if not test -e "$target"; and not test -L "$entry"
        set -l github $(__gh_parse "$target"); or return
        set -l url "https://$github[4]/$github[1]"
        if test -n "$github[2]"
            set url "$url/$(string escape --style=url -- "$github[2]")"
        end
        printf '%s%s\n' "$url" "$(string match -r '[?#].*$' -- "$target")"
        return
    end

    set -l dir "$target"
    set -l kind tree
    if test -L "$entry"; or not test -d "$target"
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
        if not test -L "$entry"
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
    if test -n "$remote"; and test "$remote" != .
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

function __gho --argument-names target
    if test "$(count $argv)" -eq 1; and contains -- "$target" -h --help
        printf '%s\n' "$usage"
        return 0
    end
    if test "$(count $argv)" -gt 1
        printf 'Usage: %s [PATH | OWNER/REPO | GITHUB_URL]\n' "$0" >&2
        return 1
    end
    set -q argv[1]; or set target "$PWD"
    set -l url "$(__gho_url "$target")"; or return
    printf '%s\n' "$url"
    open "$url"
end
