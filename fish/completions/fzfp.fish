complete -c fzfp -f
complete -c fzfp -s h -l help -d 'Show help'
complete -c fzfp -l color -d 'Color directory aliases'
complete -c fzfp -l classify -d 'Append file-type indicators'
complete -c fzfp -l keep-dot -d 'Also offer ./ paths for local scripts'
complete -c fzfp -l read0 -d 'Read NUL-separated absolute paths instead of scanning'
complete -c fzfp -l cdpath -x -d 'Search colon-separated directory roots'
complete -c fzfp -l dirali -x -a '(string join \n -- \$$aqsnow_fzf_diralis)' -d 'Map an alias name and absolute directory'
complete -c fzfp -n 'test "$(__fish_fzfp_role)" = dir' -a '(__fish_complete_directories)'
complete -c fzfp -n 'test "$(__fish_fzfp_role)" = dirali-path' -a '(__fish_fzfp_directories)'
complete -c fzfp -n 'test "$(__fish_fzfp_role)" = alias' -a '(__fish_fzfp_aliases)' -d 'Global directory alias'
complete -c fzfp -n 'test "$(__fish_fzfp_role)" = type' -a -fd -d 'Files and directories'
complete -c fzfp -n 'test "$(__fish_fzfp_role)" = type' -a -f -d 'Files only'
complete -c fzfp -n 'test "$(__fish_fzfp_role)" = type' -a -d -d 'Directories only'

function __fish_fzfp_role
    set -l tokens $(commandline -xpc)
    set -e tokens[1]
    set -l pending ''
    set -l position 1
    set -l options 1
    for token in $tokens
        switch "$pending"
            case dirali-name
                set pending dirali-path
                continue
            case dirali-path cdpath
                set pending ''
                continue
        end
        if test "$options" -eq 1
            switch "$token"
                case --
                    set options 0
                    continue
                case --dirali
                    set pending dirali-name
                    continue
                case --cdpath
                    set pending cdpath
                    continue
                case --color --classify --keep-dot --read0 -h --help
                    continue
            end
        end
        set position $(math "$position + 1")
    end
    if test -n "$pending"
        printf '%s\n' "$pending"
    else
        set -l roles dir alias type done
        printf '%s\n' "$roles[$(math "min($position, 4)")]"
    end
end

function __fish_fzfp_aliases
    set -l tokens $(commandline -xp)
    set -l previous ''
    for token in $tokens
        test "$token" = --; and break
        test "$previous" = --dirali; and printf '%s\n' "$token"
        set previous "$token"
    end
end

function __fish_fzfp_directories
    set -l prefix "$(commandline --current-token --tokens-expanded)"
    string match -q '/*' -- "$prefix"; or set prefix "$PWD/$prefix"
    __fish_complete_directories "$prefix"
end
