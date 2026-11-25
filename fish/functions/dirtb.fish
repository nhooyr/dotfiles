function dirtb --description 'List repos with indexed binary files'
    argparse --max-args 0 h/help -- $argv; or return
    if set -q _flag_help
        printf '%s\n' 'Usage: dirtb [-h|--help]
List committed and staged binary files in repositories under $nhooyr.
Skip repositories listed in $dirt_ignore.'
        return
    end
    _dirtb | tabt
end

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
