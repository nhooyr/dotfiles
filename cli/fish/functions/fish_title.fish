function fish_title
    echo -n (status current-command)" "
    echo -n (basename "$PWD")
    if [ "$hostname" != "ien" ]
        echo -n "@"(prompt_hostname)
    end
    echo
end
