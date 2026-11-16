on run
    my launchEditor("nvim")
end run

on open theFiles
    set fishPath to do shell script "PATH=/opt/homebrew/bin:/usr/local/bin:$PATH command -v fish"
    set commandText to "nvim --"
    repeat with theFile in theFiles
        set filePath to POSIX path of theFile
        set escapedPath to do shell script (quoted form of fishPath & " --no-config -c 'string escape -- $argv' -- " & quoted form of filePath)
        set commandText to commandText & " " & escapedPath
    end repeat
    my launchEditor(commandText)
end open

on launchEditor(commandText)
    tell application "/System/Applications/Utilities/Terminal.app"
        do script commandText
        activate
    end tell
end launchEditor
