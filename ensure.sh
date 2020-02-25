#!/usr/bin/env bash

set -euo pipefail

ensure() {
  ./link.sh cli/git ~/.config/git
  ./link.sh cli/nvim ~/.config/nvim
  ./link.sh cli/fish ~/.config/fish
  ./link.sh cli/mutagen/mutagen.yml ~/.mutagen.yml
  ./link.sh cli/fd/fdignore ~/.fdignore
  ./link.sh cli/gnupg ~/.gnupg
}

ensure_root() {
  sudo ./link.sh ~/.config ~root/.config
  sudo ./link.sh ~/.local ~root/.local
  sudo ./link.sh ~/src ~root/src
}

ensure_macos() {
  ./link.sh macos/gnupg/gpg-agent.conf ~/.gnupg/gpg-agent.conf
}

ensure_linux() {
  sudo cp linux/green/green.sh /usr/local/bin/green.sh
  sudo cp linux/green/green.timer /etc/systemd/system/green.timer
  sudo cp linux/green/green.service /etc/systemd/system/green.service
}

main() {
  ensure
  ensure_root

  case $OSTYPE in
  darwin*)
    ensure_macos
    ;;
  linux*)
    ensure_linux
    ;;
  esac
}

main "$@"
