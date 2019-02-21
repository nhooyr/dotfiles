function cdp
    for cdpath in $CDPATH
        if test -e "$cdpath/$argv"
            echo "$cdpath/$argv"
            return
        end
    end
end
