function fish_title
    echo -n (status current-command)" "
    if [ "$hostname" != "ien" ]
        echo -n (prompt_hostname)":"
    end
    echo (basename "$PWD")
end
