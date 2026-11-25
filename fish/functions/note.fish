function note --description '$EDITOR $notes/YYYY/MM/DD.md'
    if contains -- "$argv" -h --help
        printf 'Usage: note\nOpen $notes/YYYY/MM/DD.md in $EDITOR, creating a dated heading if needed.\n'
        return 0
    end
    set -l note "$notes/$(date '+%Y/%m/%d').md"
    if test -e "$note"
        $EDITOR "$note"
        return
    end
    printf '# %s\n* %s *\n\n\n' "$(date '+%B %d, %Y')" "$(date '+%A')" | note="$note" $EDITOR - \
        '+execute "file " . fnameescape($note)' \
        '+filetype detect' \
        '+normal! G'
end
