# Offer a target only before the first positional argument, excluding help requests.
# Callers pass any additional argparse option specifications.
function __gh_complete_target
    set -l tokens $(commandline -xpc)
    set -e tokens[1]
    argparse h/help $argv -- $tokens 2>/dev/null; or return 1
    not set -q argv[1]; and not set -q _flag_help
end
