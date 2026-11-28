function grep --wraps 'grep --color -nI'
    set -l ignore_case
    __grep_smart_case $argv; and set ignore_case -i
    if type -q ggrep
        ggrep --color -nI $ignore_case $argv
    else
        command grep --color -nI -S $ignore_case $argv
    end
end
