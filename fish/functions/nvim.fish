function nvim --wraps nvim
    if not set -q NVIM; or test -z "$NVIM"
        command nvim $argv
        return
    end
    set -l args $argv
    set -l action edit
    set -l read_stdin 0
    isatty stdin; or set read_stdin 1
    switch "$args[1]"
        case -o
            set action split
            set -e args[1]
        case -O
            set action vsplit
            set -e args[1]
    end
    if test "$args[1]" = --
        set -e args[1]
    else if test "$(count $args)" -eq 1; and test "$args[1]" = -
        set read_stdin 1
        set -e args[1]
    else if set -q args[1]; and string match -rq '^[-+]' -- $args
        command nvim $argv
        return
    end
    set -l stdin
    if not set -q args[1]; and test "$read_stdin" -eq 1
        set stdin "$(mktemp)"; or return
        if not command cat >"$stdin"
            command rm -- "$stdin"
            return 1
        end
    end
    set -l values $(string replace -a "'" "''" -- "$action" "$PWD" "$stdin" $args)
    set -l request "['$(string join "','" -- $values)']"
    command nvim --server "$NVIM" --remote-expr "luaeval('require(\"terminal\").open(_A)', $request)" >/dev/null
    set -l result $status
    test -z "$stdin"; or command rm -- "$stdin"
    return "$result"
end
