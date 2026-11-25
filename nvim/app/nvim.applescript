on run
    my launchEditor("nvim")
end run

on open theFiles
    my launchEditor(my commandForFiles(theFiles))
end open

on commandForFiles(theFiles)
    set fishPath to do shell script "PATH=/opt/homebrew/bin:/usr/local/bin:$PATH command -v fish"
    set argumentsText to ""
    repeat with theFile in theFiles
        set argumentsText to argumentsText & " " & quoted form of (POSIX path of theFile)
    end repeat
    return do shell script (quoted form of fishPath & " --no-config -c 'printf \"nvim --\"; for file in $argv; printf \" %s\" $(string escape -- \"$file\"); end' --" & argumentsText)
end commandForFiles

on launchEditor(commandText)
    tell application "/System/Applications/Utilities/Terminal.app"
        do script commandText
        activate
    end tell
end launchEditor
