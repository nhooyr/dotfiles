function colors
    for name in black red green yellow blue magenta cyan white
        printf '%s\t%s\n' "$(set_color "$name")$name" "$(set_color "br$name")br$name"
    end
    set_color reset
end
