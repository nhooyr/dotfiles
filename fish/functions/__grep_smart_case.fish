function __grep_smart_case
    # Unknown options opt out of smart case.
    argparse E F G R e/regexp=+ -- $argv 2>/dev/null; or return 1
    set -l patterns $_flag_regexp
    set -q patterns[1]; or set patterns $argv[1]
    set -q patterns[1]; and not string match -qr '\p{Uppercase}' -- $patterns
end
