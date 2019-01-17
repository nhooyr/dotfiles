function ls
    if isatty 1
        if test (uname) = Darwin
            # TODO better colors
            command ls -GF $argv
        else
            command ls --color --indicator-style=classify $argv
        end
    else
        command ls $argv
    end
end
