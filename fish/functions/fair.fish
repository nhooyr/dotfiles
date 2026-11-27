function fair --description 'fair [n] [--date1 YYYY-MM-DD --date2 YYYY-MM-DD] | fair --sort'
    set -l arguments $argv
    argparse --ignore-unknown h/help sort -- $argv; or return
    if set -q _flag_sort; and not set -q _flag_help; and not set -q argv[1]
        cd -- "$fair"; or return
    end
    fair="$fair" "$dotfiles/fish/functions/fair.pl" $arguments
end
