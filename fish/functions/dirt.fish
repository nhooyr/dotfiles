alias dirt='_dirt | tabt'
function _dirt --description 'List repos with dirt'
    for gitdir in ~/code/*/.git ~/code/*/*/.git
        set -l dir "$(path dirname -- "$gitdir")"
        if contains -- "$dir" $dirt_ignore
            continue
        end
        set -l prompt "$(cdc "$dir" fish_git_prompt '%s')"; or continue
        set -l flags "$(string split --max 1 --fields 2 -- ' ' "$prompt")"
        if test -n "$flags"
            set -l name "$(string replace ~/code/ '' "$dir")"
            printf '%s\t%s\n' "$name" "$flags"
        end
    end
end
