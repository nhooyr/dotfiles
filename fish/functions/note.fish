function note --description '$EDITOR $notes/YYYY/MM/DD.md'
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
