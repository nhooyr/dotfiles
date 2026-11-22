function ghss --description 'Upload a screenshot to GitHub and copy its Markdown'
    set -l usage 'Usage: ghss [PHOTO]

Upload a PNG or JPEG to the current GitHub repository.
Without a path, read a macOS clipboard image using pngpaste.
Validate the image, then print its Markdown and copy it with pbc.
Uses gh authentication and repository selection; requires write access.'
    0="$(status current-function)" usage="$usage" __ghss $argv
end

function __ghss_upload --argument-names directory
    set -l photo "$directory/image"
    if set -q argv[2]
        cp -- "$argv[2]" "$photo"; or return
    else
        pngpaste - >"$photo"; or return
    end
    set -l size $(stat -f %z -- "$photo"); or return
    if test "$size" -gt 10485760
        printf '%s: image must be at most 10 MiB\n' "$0" >&2
        return 1
    end
    set -l content_type "$(file --brief --mime-type -- "$photo")"; or return
    if not contains -- "$content_type" image/png image/jpeg
        printf '%s: expected a PNG or JPEG image\n' "$0" >&2
        return 1
    end
    sips -s format png "$photo" --out "$directory/decoded.png" >/dev/null; or return
    set -l repository $(gh api --hostname github.com 'repos/{owner}/{repo}' --jq .id); or return
    set -l url "$(gh api --hostname github.com https://uploads.github.com/user-attachments/assets \
        --method POST \
        --input "$photo" \
        -H 'Accept: application/vnd.github+json' \
        -H 'Content-Type: application/octet-stream' \
        -H "Content-Length: $size" \
        -f "name=screenshot.$(string replace image/ '' -- "$content_type")" \
        -f "content_type=$content_type" \
        -F "repository_id=$repository" \
        --jq '.url // empty')"; or return
    test -n "$url"; or return 1
    printf '![img](%s)\n' "$url" | pbc
end

function __ghss
    argparse --name "$0" --max-args 1 h/help -- $argv; or return
    if set -q _flag_help
        printf '%s\n' "$usage"
        return 0
    end
    set -l directory "$(mktemp -d)"; or return
    __ghss_upload "$directory" $argv
    set -l result "$status"
    rm -rf -- "$directory"
    return "$result"
end
