function touch --wraps touch
    set -l args $argv
    argparse --stop-nonopt A= a c d= f h m r= t= -- $argv; or return
    if set -q argv[1]; and not set -q _flag_c; and not set -q _flag_A; and not set -q _flag_h
        command mkdir -p -- $(path dirname -- $argv); or return
    end
    command touch $args
end
