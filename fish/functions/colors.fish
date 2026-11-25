function colors
    if contains -- "$argv" -h --help
        printf 'Usage: colors\nPreview the normal and bright terminal colors.\n'
        return 0
    end
    for name in black red green yellow blue magenta cyan white
        printf '%s\t%s\n' "$(set_color "$name")$name" "$(set_color "br$name")br$name"
    end
    set_color reset
end
