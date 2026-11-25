alias dirtb='_dirtb | tabt'
function _dirtb --description 'List repos with indexed binary files'
    for gitdir in "$nhooyr"/*/.git
        set -l dir "$(path dirname -- "$gitdir")"
        contains -- "$dir" $dirt_ignore; and continue
        set -l files $(cdc "$dir" gbins); or continue
        set -l name "$(string replace ~/code/ '' "$dir")"
        for file in $files
            printf '%s\t%s\n' "$name" "$file"
        end
    end
end
