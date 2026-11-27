# Complete OWNER/REPO from ~/code/OWNER/REPO checkouts without querying GitHub.
function __gh_complete_repositories
    for gitdir in ~/code/*/*/.git
        set -l repository "$(string replace -- "$HOME/code/" '' "$(path dirname -- "$gitdir")")"
        if string match -qr '^[A-Za-z0-9][A-Za-z0-9_-]*/[A-Za-z0-9._-]+$' -- "$repository"
            printf '%s\tLocal checkout\n' "$repository"
        end
    end
end
