function gg --wraps 'git grep -IE --recurse-submodules'
    set -l ignore_case
    __grep_smart_case $argv; and set ignore_case -i
    git grep -IE --recurse-submodules $ignore_case $argv
end
