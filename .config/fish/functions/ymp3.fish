function ymp3
    if test (count $argv) -eq 0
        set argv (osascript -e 'tell application "Safari" to return URL of front document')
    end
    cd (mktemp -d)
    if youtube-dl --no-playlist --extract-audio --audio-format mp3 --default-search ytsearch $argv
        mv * "$HOME/Music/iTunes/iTunes Media/Automatically Add to iTunes.localized"
    end
    prevd
end
