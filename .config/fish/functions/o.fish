function o
    set -l path (rg --files --hidden --no-ignore | fzf)
    if [ "$path" = "" ]
        return
    end
    if [ -f $path ]
        e $path
    else
        cd $path
    end
end