function biglines --argument-names file \
    --description 'Print lines in a file with their lengths, sorted by length'
    if contains -- "$argv" -h --help
        printf 'Usage: biglines FILE|-\nShow lines and their lengths in a pager, longest first. Use - for standard input.\n'
        return 0
    end
    if test "$file" != -; and not string match -q '/*' -- "$file"
        set file "./$file"
    end
    awk '{ print length, $0 }' "$file" | sort -rn \
        | sed -E "s/^[0-9]+/$(set_color magenta)&$(set_color reset)/" | less
    for code in $pipestatus
        contains -- "$code" 0 141; or return "$code"
    end
end
