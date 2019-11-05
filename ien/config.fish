source /usr/local/opt/fzf/shell/key-bindings.fish
fzf_key_bindings

alias ls="gls --indicator-style=classify --color=auto"
alias icloud="cd ~/Library/Mobile\ Documents/com~apple~CloudDocs"
alias bu="brew update && brew upgrade && brew cask upgrade"
alias b="brew"
alias i="brew install"
alias fp="fp.js"
alias ports="netstat -vanp tcp"

function tra
    for file in $argv
        set -l file (realpath "$file")
        osascript -e "tell application \"Finder\" to delete POSIX file \"$file\"" >/dev/null
    end
end

function ms
    set -l localPath (realpath "$argv")
    set -l remotePath (xpath "$localPath")
    mutagen sync create -n=(basename "$localPath") "$localPath" xayah-unshared:"$remotePath"
end

# https://stackoverflow.com/a/58445755/4283659
# x2go's CLI needs this.
set -gx DYLD_LIBRARY_PATH /usr/local/opt/openssl/lib

addToPath ~/.cargo/bin
addToPath /usr/local/opt/make/libexec/gnubin
addToPath /usr/local/opt/gnu-sed/libexec/gnubin
addToPath ~/src/nhooyr/dotfiles/ien/bin

# https://github.com/fish-shell/fish-shell/issues/6270#issuecomment-548515306
function __fish_describe_command
end

# set -gx NOTI_NSUSER_SOUNDNAME Glass
