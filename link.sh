#!/bin/sh
set -eu

ensure() {
  ./ci/link.sh nvim ~/.config/nvim
  ./ci/link.sh zsh/zshrc ~/.zshrc
  ./ci/link.sh fish ~/.config/fish
  ./ci/link.sh emacs ~/.emacs.d

  ./ci/link.sh git ~/.config/git
  ./ci/link.sh secrets/gnupg ~/.gnupg
  ./ci/link.sh secrets/ssh ~/.ssh
  ./ci/link.sh ssh/config ~/.ssh/config

  # Otherwise ssh and gpg will complain.
  find secrets -type f -exec chmod 600 {} \;
  find secrets -type d -exec chmod 700 {} \;

  # Required for SSH multiplexing.
  mkdir -p ~/.ssh/sockets

  ./ci/link.sh fd ~/.config/fd
}

ensure_root() {
  sudo ./ci/link.sh ~/.config ~root/.config
  sudo ./ci/link.sh ~/.local ~root/.local
}

main() {
  cd "$(dirname "$0")"
  git submodule update --init

  ensure
  ensure_root
}

main "$@"
