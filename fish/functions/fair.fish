function fair --description 'fair [n] [--date1 YYYY-MM-DD --date2 YYYY-MM-DD] | fair --sort'
    set -l arguments $argv
    argparse --max-args 1 --exclusive sort,date1 --exclusive sort,date2 sort date1= date2= -- $argv; or return
    if set -q _flag_sort
        if set -q argv[1]
            printf '%s: --sort does not accept a count\n' "$(status function)" >&2
            return 2
        end
        cd -- "$fair_repo"; or return
        perl "$dotfiles/fish/fair_sort.pl"
        return "$status"
    end
    if test "$(path resolve -- "$PWD")" != "$(path resolve -- "$fair_repo")"
        cdc "$fair_repo" fair $arguments
        return
    end
    set -l n "$argv[1]"
    test -n "$n"; or set n 1
    if not string match -qr '^[0-9]{1,5}$' -- "$n"; or test "$n" -lt 1
        printf '%s: 1 <= n <= 99999\n' "$(status function)" >&2
        return 1
    end
    set -l dates
    if set -q _flag_date1; or set -q _flag_date2
        if not set -q _flag_date1; or not set -q _flag_date2
            printf '%s: --date1 and --date2 must be provided together\n' "$(status function)" >&2
            return 1
        end
        set dates $(perl "$dotfiles/fish/fair_dates.pl" "$_flag_date1" "$_flag_date2" "$n"); or return
    end
    set -l msg "$(git show -s --format=%s)"
    set -l msgn "$(string match -rg ': ([0-9]+)$' -- "$msg")"; or set msgn 0
    for i in $(seq 1 "$n")
        set msgn "$(math "$msgn" + 1)"
        if set -q dates[$i]
            set -fx GIT_AUTHOR_DATE "@$dates[$i] +0000"
            set -fx GIT_COMMITTER_DATE "$GIT_AUTHOR_DATE"
        end
        git commit --allow-empty --only -m "count: $msgn"; or return
    end
    git push
end
