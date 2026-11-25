function biglines --argument-names file \
    --description 'Print lines in a file with their lengths, sorted by length'
    awk '{ print length, $0 }' "$file" | sort -rn \
        | sed -E "s/^[0-9]+/$(set_color magenta)&$(set_color reset)/" | less
end
