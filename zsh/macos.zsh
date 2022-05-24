export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_CLEANUP=1
export HOMEBREW_NO_EMOJI=1

tputq() {
  tput "$@" | sed "s#\[#\\\[#"
}

brew() {
  # Replace bold with underline.
  # https://github.com/Homebrew/brew/issues/7753
  HOMEBREW_COLOR=1 command brew "$@" | sed "s/$(tputq bold)/$(tputq smul)/g"
}

if [[ ! "$REMOTE_HOST" ]]; then
  export REMOTE_HOST="$USER@xayah"
  # export REMOTE_HOST="$USER@xayah.local"
fi

alias b="brew"
alias bc="brew cask"
alias bs="brew search"
alias bi="brew install"
alias br="brew remove"
alias bu="brew update && brew upgrade && brew upgrade --cask"
alias ports="netstat -vanp tcp"
alias uti="mdls -name kMDItemContentTypeTree"
alias o="open"
alias o.="open ."

prepend_PATH /usr/local/sbin
prepend_PATH /usr/local/opt/llvm/bin
prepend_PATH /usr/local/opt/make/libexec/gnubin
# prepend_PATH /usr/local/opt/gnu-sed/libexec/gnubin
prepend_PATH /usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/bin
prepend_PATH /usr/local/opt/node@12/bin

prepend_path FPATH /usr/local/share/zsh-completions
# Always use zsh's _git completion instead of the one bundled with git.
rm -f /usr/local/share/zsh/site-functions/_git
rm -f /opt/homebrew/share/zsh/site-functions/_git
prepend_PATH /opt/homebrew/bin

# Has to be loaded after completion.
post_os_zshrc() {
  source_if_exists "/usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/completion.zsh.inc" || true
  source_if_exists "/opt/homebrew/bin/google-cloud-sdk/latest/google-cloud-sdk/completion.zsh.inc" || true
}

# I didn't name this chromium as a show of respect towards the author of
# ungoogled-chromium.
eloston() {
  (
    /Applications/Chromium.app/Contents/MacOS/Chromium \
    --disable-features=ExtensionsToolbarMenu $@ &>/dev/null &!
  )
}

# Python on M1 macs is shit.
export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES
