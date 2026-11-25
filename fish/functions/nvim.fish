function nvim --wraps nvim
    if not set -q NVIM; or test -z "$NVIM"; or not isatty stdin
        command nvim $argv
        return
    end
    set -l args $argv
    set -l action edit
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
    else if set -q args[1]; and string match -rq '^[-+]' -- $args
        command nvim $argv
        return
    end
    set -l values $(string replace -a "'" "''" -- "$action" "$PWD" $args)
    set -l request "['$(string join "','" -- $values)']"
    command nvim --server "$NVIM" --remote-expr "luaeval('require(\"terminal\").open(_A)', $request)" >/dev/null
end
