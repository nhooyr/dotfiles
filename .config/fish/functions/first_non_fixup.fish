function first_non_fixup
    git log --pretty='%H' -1 --invert-grep --grep 'fixup! '
end
