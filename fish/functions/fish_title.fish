function fish_title
    if [ "$hostname" != "ien" ]
        echo -n @(prompt_hostname) " "
    end
    if [ "$argv" = "" ]
        echo -n (status current-command)
    else
        echo "$argv"
    end
    echo " " :(prompt_pwd)
end
