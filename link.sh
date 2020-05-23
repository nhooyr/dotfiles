#!/bin/sh
set -eu

ensure() {
  ./ci/link.sh git ~/.config/git
  ./ci/link.sh secrets/gnupg ~/.gnupg
  ./ci/link.sh secrets/ssh ~/.ssh
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
