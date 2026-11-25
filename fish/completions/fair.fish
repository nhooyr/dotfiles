complete -c fair -f
complete -c fair -n 'not __fish_seen_argument -l date1 -l date2' -l sort -d 'Redistribute existing commit dates'
complete -c fair -n 'not __fish_seen_argument -l sort' -l date1 -x -d 'First date (YYYY-MM-DD)'
complete -c fair -n 'not __fish_seen_argument -l sort' -l date2 -x -d 'Last date (YYYY-MM-DD)'
complete -c fair -n __fish_fair_count -a 1 -d 'Commit count (1–99999)'

function __fish_fair_count
    set -l tokens $(commandline -xpc)
    set -e tokens[1]
    argparse sort date1= date2= -- $tokens 2>/dev/null; or return 1
    not set -q argv[1]; and not set -q _flag_sort
end
