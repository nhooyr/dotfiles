function gg --wraps 'git grep -IE --untracked --no-recurse-submodules'
    set -l ignore_case
    __grep_smart_case $argv; and set ignore_case -i
    git grep -IE --untracked --no-recurse-submodules $ignore_case $argv
end
