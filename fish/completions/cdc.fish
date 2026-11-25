complete -c cdc -f
complete -c cdc -n 'test "$(count $(commandline -xpc))" -eq 1' -a '(__fish_complete_directories)'
complete -c cdc -n 'test "$(count $(commandline -xpc))" -ge 2' -x -a '(__fish_cdc_command)'

function __fish_cdc_command
    set -l tokens $(commandline -xpc)
    set -l previous "$PWD"
    builtin cd -- "$tokens[2]" 2>/dev/null; or return
    __fish_complete_subcommand --fcs-skip=2
    builtin cd -- "$previous"
end
