function cdf --wraps cd --argument-names file
    CDPATH=. cd -- "$(path dirname -- "$file")"
end
