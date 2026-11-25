complete -c sshf -f
complete -c sshf -n 'test "$(count $(commandline -xpc))" -eq 1' -s h -l help -d 'Show help'
complete -c sshf -n 'test "$(count $(commandline -xpc))" -eq 1; or __fish_prev_arg_in -L' -s L -x -a 0 -d 'Forward a local source port to the server'
complete -c sshf -n 'test "$(count $(commandline -xpc))" -eq 1; or __fish_prev_arg_in -R' -s R -x -a 0 -d 'Forward a server source port locally'
complete -c sshf -n 'test "$(count $(commandline -xpc))" -eq 1' -s D -d 'Use the server as the macOS SOCKS proxy'
complete -c sshf -a '(__fish_sshf_complete)'

function __fish_sshf_complete
    set -l tokens $(commandline -xpc)
    switch "$tokens[2]"
        case -D
            set -e tokens[1..2]
        case -L -R
            test "$(count $tokens)" -ge 3; or return
            set -e tokens[1..3]
            if string match -qr '^[0-9]+$' -- "$tokens[1]"
                set -e tokens[1]
            else if not set -q tokens[1]; and string match -qr '^[0-9]+$' -- "$(commandline -ct)"
                return
            end
        case '*'
            return
    end
    set -l line "ssh $(string join ' ' -- $(string escape -- $tokens)) $(commandline -ct)"
    complete -C "$line"
end
