function fish_title
    if [ "$hostname" != "ien" ]
        echo -n @(prompt_hostname) " "
    end
    set -l cmd (status current-command)
    if [ "$argv" != "" ]
        set cmd "$argv"
    end
    echo -n "$cmd"
    echo " " :(prompt_pwd)
end
