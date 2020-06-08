#!/bin/sh
set -eu

main() {
  export DEBIAN_FRONTEND=noninteractive

  sudo -E apt update
  install_dotfiles

  sudo -E apt full-upgrade -y --purge
  sudo -E apt autoremove -y --purge
  sudo -E apt install -y \
    rsync \
    jq \
    build-essential \
    cmake \
    git

  install_go
  install_node
  install_neovim
}

install_node() {
  curl -fsSL https://deb.nodesource.com/setup_14.x | sudo -E bash -
  sudo apt-get install -y nodejs

  sudo npm install -g yarn
  yarn global add \
    vim-language-server \
    typescript \
    typescript-language-server
}

install_go() {
  sudo -E apt install -y golang

  export GOPATH="$HOME/.local/share/gopath"
  export GO111MODULE=on
  go get golang.org/x/tools/gopls@latest
  go get mvdan.cc/sh/v3/cmd/shfmt@latest
}

install_docker() {
  sudo -E apt install -y docker.io
  sudo groupadd -f docker
  sudo usermod -aG docker "$USER"
  newgrp docker
}

install_dotfiles() {
  sudo -E apt install -y \
    git \
    zsh \
    fzf \
    fd-find
  if [ ! -d ~/src/nhooyr/dotfiles ]; then
    mkdir -p ~/src/nhooyr
    git clone https://github.com/nhooyr/dotfiles ~/src/nhooyr/dotfiles
  fi
  git -C ~/src/nhooyr/dotfiles submodule update --init
  git -C ~/src/nhooyr/dotfiles pull
  ~/src/nhooyr/dotfiles/link.sh
  sudo chsh -s "$(command -v zsh)" "$USER"
}

install_neovim() {
  # https://github.com/neovim/neovim/wiki/Building-Neovim
  sudo -E apt install -y ninja-build gettext libtool libtool-bin autoconf automake cmake g++ pkg-config unzip
  if [ ! -d ~/src/neovim/neovim ]; then
    mkdir -p ~/src/neovim
    git clone https://github.com/neovim/neovim ~/src/neovim/neovim
  fi
  cd ~/src/neovim/neovim
  make CMAKE_BUILD_TYPE=RelWithDebInfo
  sudo make install
  cd -
}

main "$@"
