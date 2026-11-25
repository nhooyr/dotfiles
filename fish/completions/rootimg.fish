complete -c rootimg -f
complete -c rootimg -n 'test "$(count $(commandline -xpc))" -eq 1' -s h -l help -d 'Show usage'
complete -c rootimg -n 'test "$(count $(commandline -xpc))" -eq 1' -k \
    -a '(__fish_complete_suffix .avif .bmp .gif .heic .ico .jpeg .jpg .png .svg .tif .tiff .webp)'
