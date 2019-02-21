function g_checkout_push
    if git rev-parse --verify $argv > /dev/null
        git checkout $argv
        and git push --set-upstream
    else
        git checkout -b $argv
        and git push --set-upstream
    end
end
