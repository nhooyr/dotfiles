function grep --wraps 'grep --color -nI'
    set -l args $argv
    set -l ignore_case
    # Keep this smart-case block in sync with gg.fish.
    # Only -E/-F/-G/-R and -e/--regexp are understood; unknown options opt out.
    if argparse E F G R e/regexp=+ -- $argv 2>/dev/null
        set -l patterns $_flag_regexp
        set -q patterns[1]; or set patterns $argv[1]
        if set -q patterns[1]; and not string match -qr '\p{Uppercase}' -- $patterns
            set ignore_case -i
        end
    end
    if type -q ggrep
        ggrep --color -nI $ignore_case $args
    else
        command grep --color -nI -S $ignore_case $args
    end
end
