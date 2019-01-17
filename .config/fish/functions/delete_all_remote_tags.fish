function delete_all_remote_tags
    git push --delete origin (git tag -l)
end
