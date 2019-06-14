function up
    if test -e $argv
        # Idea here is numbers go up n directories, not sure if I want this though, seems confusing
        # or math $argv >/dev/null 2>&1
        # up_n $argv
        cd ..
        return
    end
    up_d $argv
end

function up_n
    set -l count "$argv"
    if [ -z "$count" ]
        set count 1
    end
    cd (string join .. (string repeat -n $count ' /' | string split ' '))
end

function up_d
    set -l pwd (string split --no-empty '/' $PWD)
    # Reverse directories.
    set -l pwd $pwd[-1..1]
    # Skip current directory.
    set -l pwd $pwd[2..-1]
    for i in (seq (count $pwd))
        if echo $pwd[$i] | rg -q $argv
            up_n $i
            return
        end
    end
end