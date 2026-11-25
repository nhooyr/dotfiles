function gbins --description 'Print staged or committed binary files'
    set -l empty_tree "$(git hash-object -t tree /dev/null)"; or return
    git diff --numstat --cached "$empty_tree" | awk -F '\t' '$1 == "-" {print $3}'
end
