function gbigdirs --description 'Show the largest directories using Git-tracked files'
    git rev-parse --show-toplevel >/dev/null; or return
    git ls-files --recurse-submodules --deduplicate -z |
        while read -zl file
            if test -f "$file"; or test -L "$file"
                printf './%s\0' "$file"
            end
        end |
        gdu -B1 --files0-from=- |
        awk -F '\t' '
            {
                size = $1
                path = substr($0, index($0, "\t") + 1)
                sub(/^\.\//, "", path)
                total += size
                if (sub(/\/.*/, "", path)) sizes[path] += size
            }
            END {
                printf "%.0f\t.\n", total
                for (dir in sizes)
                    printf "%.0f\t./%s\n", sizes[dir], dir
            }
        ' |
        sort -k1,1nr -k2 |
        head -n 16 |
        gnumfmt --delimiter=\t --field=1 --to=iec
end
