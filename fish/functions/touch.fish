function touch --wraps touch
    set -l options $argv
    argparse --stop-nonopt A= a c d= f h m r= t= -- $argv; or return
    if set -q argv[1]; and not set -q _flag_c; and not set -q _flag_A; and not set -q _flag_h
        command mkdir -p -- $(path dirname -- $argv) $(string match -- '*/' $argv); or return
    end
    set -l files $(string match -v -- '*/' $argv)
    if set -q argv[1]
        set -q files[1]; or return 0
        set -e "options[-$(count $argv)..-1]"
    end
    command touch $options $files
end
