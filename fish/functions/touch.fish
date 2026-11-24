function touch --wraps touch
    set -l args $argv
    argparse --stop-nonopt A= a c d= f h m r= t= -- $argv; or return
    if set -q argv[1]; and not set -q _flag_c; and not set -q _flag_A; and not set -q _flag_h
        command mkdir -p -- $(path dirname -- $argv) $(string match -- '*/' $argv); or return
    end
    if set -q argv[1]
        set -l files $(string match -v -- '*/' $argv)
        set -q files[1]; or return 0
        set -l count $(count $argv)
        set -e args[-$count..-1]
        set -a args $files
    end
    command touch $args
end
