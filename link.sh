#!/bin/sh
set -eu

main() {
  cd "$(dirname "$0")"

  ./ln.sh git ~/.config/git
  ./ln.sh nvim ~/.config/nvim
  ./ln.sh zsh/zshrc ~/.zshrc
  ./ln.sh fd ~/.config/fd
  ./ln.sh tmux/tmux.conf ~/.tmux.conf

  # Required for SSH multiplexing.
  mkdir -p ~/.ssh/sockets
  chmod 700 ~/.ssh
  ./ln.sh ssh/config ~/.ssh/config
  sudo mkdir -p ~root/.ssh/sockets
  sudo chmod 700 ~root/.ssh
  sudo ./cp.sh ssh/config ~root/.ssh/config

  if [ -f /etc/os-release ]; then
    DISTRO="$(. /etc/os-release && echo "$ID")"
    if [ "$DISTRO" = "debian" ]; then
      ./debian/link.sh
    fi
  fi

  if [ -f ./secrets/link.sh ]; then
    ./secrets/link.sh
  fi
}

main "$@"
