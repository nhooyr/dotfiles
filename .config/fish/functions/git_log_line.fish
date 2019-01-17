function git_log_line
    if test (count $argv) != 3
        echo "usage: "(status function)" <range_start> <range_end> <file_name>" >/dev/stderr
        return
    end
    git log "-L$argv[1],$argv[2]:$argv[3]"
end