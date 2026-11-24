function rootimg --description 'Shrink image to 1/4' --argument-names img
    if test -z "$img"; or set -q argv[2]
        printf 'Usage: %s <img>\n' "$(status current-function)" >&2
        return 1
    end
    if contains -- "$img" -h --help
        printf 'Usage: %s <img>\n' "$(status current-function)"
        return 0
    end
    set -l img_dst "$(path basename --no-extension "$img")"
    set img_dst "$img_dst-root$(path extension "$img")"
    set img_dst "$(path dirname "$img")/$img_dst"
    magick "$img" -resize 50% "$img_dst"
end
