DOTFILES="$HOME/src/nhooyr/dotfiles"

# Homebrew takes forever to update.
export HOMEBREW_NO_AUTO_UPDATE=1
export GOPATH=~/.local/share/gopath

export EDITOR="nvim"
export MANPAGER="nvim +Man!"
export MANWIDTH=80

prepend_path() {
  if [[ $PATH != *$1:* ]]; then
    PATH="$1:$PATH"
  fi
}

prepend_path "$GOPATH/bin"

prepend_cdpath() {
  if [[ ! $CDPATH ]]; then
    CDPATH="$1"
    return
  fi

  if [[ $CDPATH != *$1:* ]]; then
    CDPATH="$1:$CDPATH"
  fi
}

prepend_cdpath ~/src
prepend_cdpath ~/.config
prepend_cdpath ~/src/cdr
prepend_cdpath ~/src/nhooyr
prepend_cdpath ~/src/nhooyr/dotfiles
prepend_cdpath .
