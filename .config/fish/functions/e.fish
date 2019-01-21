function e
    mkdir -p (dirname $argv)
    and touch $argv
    and open -a Xcode $argv
end
