function dirt --description 'List repos with dirt'
    argparse --max-args 0 h/help -- $argv; or return
    if set -q _flag_help
        printf '%s\n' 'Usage: dirt [-h|--help]
List Git status flags for repositories under ~/code.
Skip repositories listed in $dirt_ignore.'
        return
    end
    _dirt | tabt
end

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
