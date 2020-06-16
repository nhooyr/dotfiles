export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_COLOR=1

if [[ ! "$REMOTE_HOST" ]]; then
  export REMOTE_HOST="$USER@xayah"
fi

alias b="brew"
alias bs="brew search"
alias bc="brew cask"
alias bu="brew update && brew upgrade && brew cask upgrade"
alias i="brew install"
alias ic="brew cask install"
alias u="brew remove"
alias uc="brew cask remove"
alias ports="netstat -vanp tcp"
alias uti="mdls -name kMDItemContentTypeTree"
alias o="open"

prepend_PATH /usr/local/sbin
prepend_PATH /usr/local/opt/llvm/bin
prepend_PATH /usr/local/opt/make/libexec/gnubin
prepend_PATH /usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/bin

prepend_path FPATH /usr/local/share/zsh-completions

# Has to be loaded after completion.
post_os_zshrc() {
  source "/usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/completion.zsh.inc"
}
