export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_COLOR=1

export REMOTE_HOST="xayah"

alias b="brew"
alias bu="brew update && brew upgrade && brew cask upgrade"
alias i="brew install"
alias u="brew remove"
alias ports="netstat -vanp tcp"
alias uti="mdls -name kMDItemContentTypeTree"
alias o="open"

prepend_PATH /usr/local/sbin
prepend_PATH /usr/local/opt/llvm/bin
prepend_PATH /usr/local/opt/make/libexec/gnubin
prepend_PATH /usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/bin

noti() {
  local last_status="$?"
  if [[ "$#" -eq 0 ]]; then
    if [[ "$last_status" -eq 0 ]]; then
      set -- true
    else
      set -- false
    fi
  fi
  if "$@"; then
    afplay /System/Library/Sounds/Glass.aiff &!
  else
    osascript -e beep &!
  fi
}

prepend_path FPATH /usr/local/share/zsh-completions
# Disables ~<USER> completion. Way too many on macOS.
# I only want to see my bookmarks.
zstyle ":completion:*" users

# Has to be loaded after completion.
post_os_zshrc() {
  source "/usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/completion.zsh.inc"
}
