#!/bin/sh
set -eu

main() {
  export DEBIAN_FRONTEND=noninteractive

  sudo -E apt update
  sudo -E apt full-upgrade -y --purge
  sudo -E apt autoremove -y --purge
  sudo -E apt install -y \
    rsync \
    jq \
    build-essential \
    cmake \
    git \
    curl

  install_dotfiles

  install_go
  install_node
  install_neovim
  install_docker
  install_misc
  install_exa
}

install_node() {
  curl -fsSL https://deb.nodesource.com/setup_14.x | sudo -E bash -
  sudo apt-get install -y nodejs

  sudo npm install -g yarn
  yarn config set prefix ~/.local
  yarn global add \
    vim-language-server \
    typescript \
    typescript-language-server \
    prettier \
    doctoc
}

install_go() {
  sudo -E apt install -y golang

  export GOPATH="$HOME/.local/share/gopath"
  export GO111MODULE=on
  go get golang.org/x/tools/gopls@latest
  go get mvdan.cc/sh/v3/cmd/shfmt@latest
  go get golang.org/x/tools/cmd/goimports@latest
  go get golang.org/x/tools/cmd/stringer@latest
  go get golang.org/x/lint/golint@latest
  go get github.com/agnivade/wasmbrowsertest@latest
}

install_docker() {
  sudo -E apt install -y docker.io
  sudo groupadd -f docker
  sudo usermod -aG docker "$USER"
  newgrp docker
}

install_dotfiles() {
  sudo -E apt install -y \
    zsh \
    fzf \
    fd-find
  if [ ! -d ~/src/nhooyr/dotfiles ]; then
    mkdir -p ~/src/nhooyr
    git clone --recurse-submodules https://github.com/nhooyr/dotfiles ~/src/nhooyr/dotfiles
  fi
  ~/src/nhooyr/dotfiles/link.sh
  sudo chsh -s "$(command -v zsh)" "$USER"
}

install_neovim() {
  sudo -E apt install -y python3-neovim
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

install_misc() {
  sudo -E apt install -y shellcheck ripgrep htop tmux
}

install_exa() {
  if command -v exa > /dev/null; then
    return
  fi

  cd "$(mktemp -d)"
  curl -fsSL -O https://github.com/ogham/exa/releases/download/v0.9.0/exa-linux-x86_64-0.9.0.zip
  unzip exa-linux-x86_64-0.9.0.zip
  sudo mv exa-linux-x86_64 /usr/local/bin/exa
  rm exa-linux-x86_64-0.9.0.zip
  cd -
}

main "$@"
