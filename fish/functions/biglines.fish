function biglines --argument-names file \
    --description 'Print lines in a file with their lengths, sorted by length'
    if test "$file" != -; and not string match -q '/*' -- "$file"
        set file "./$file"
    end
    awk '{ print length, $0 }' "$file" | sort -rn \
        | sed -E "s/^[0-9]+/$(set_color magenta)&$(set_color reset)/" | less
    for code in $pipestatus
        contains -- "$code" 0 141; or return "$code"
    end
end
