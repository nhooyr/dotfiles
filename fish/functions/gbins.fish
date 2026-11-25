function gbins --description 'Print staged or committed binary files'
    if contains -- "$argv" -h --help
        printf '%s\n' 'Usage: gbins
List binary files in the Git index, including committed and staged files.'
        return
    end
    set -l empty_tree "$(git hash-object -t tree /dev/null)"; or return
    git diff-index --numstat --cached "$empty_tree" | awk -F '\t' '$1 == "-" {print $3}'
    return "$pipestatus[1]"
end
