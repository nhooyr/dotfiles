#!/bin/sh
set -eu

main() {
  cd "$(dirname "$0")"

  ./ci/link.sh nvim ~/.config/nvim
  ./ci/link.sh zsh/zshrc ~/.zshrc
  ./ci/link.sh fish ~/.config/fish
  ./ci/link.sh emacs ~/.emacs.d

  ./ci/link.sh git ~/.config/git
  ./ci/link.sh fd ~/.config/fd

  # Required for SSH multiplexing.
  mkdir -p ~/.ssh/sockets
  chmod 700 ~/.ssh
  ./ci/link.sh ssh/config ~/.ssh/config

  ./secrets/link.sh
}

main "$@"
