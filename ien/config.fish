source /usr/local/opt/fzf/shell/key-bindings.fish
fzf_key_bindings

alias ls="gls --indicator-style=classify --color=auto"
alias icloud="cd ~/Library/Mobile\ Documents/com~apple~CloudDocs"
alias bu="brew update && brew upgrade && brew cask upgrade"
alias b="brew"
alias i="brew install"
alias fp="fp.js"
alias ports="netstat -vanp tcp"
alias lfs="ssh lfs"

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

addToPath ~/.cargo/bin
addToPath /usr/local/opt/make/libexec/gnubin
addToPath /usr/local/opt/gnu-sed/libexec/gnubin
addToPath ~/src/nhooyr/dotfiles/ien/bin

# https://github.com/fish-shell/fish-shell/issues/6270#issuecomment-548515306
function __fish_describe_command
end
