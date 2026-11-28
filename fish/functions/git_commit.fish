function git_commit --wraps 'git commit'
    git -c status.relativePaths=false commit $argv
end
