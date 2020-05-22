function fish_title
    echo -n (status current-command)" "
    echo -n (prompt_pwd)
    if [ "$hostname" != "ien" ]
        echo -n "@"(prompt_hostname)
    end
    echo
end
