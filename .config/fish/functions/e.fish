function e
    mkdir -p (dirname $argv)
    and touch $argv
    and editor $argv
end
