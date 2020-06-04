alias bu="brew update && brew upgrade && brew cask upgrade"
alias b="brew"
alias i="brew install"
alias u="brew remove"
alias ports="netstat -vanp tcp"

prepend_path /usr/local/sbin
prepend_path /usr/local/opt/llvm/bin

source "/usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.zsh.inc"
source "/usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/completion.zsh.inc"
