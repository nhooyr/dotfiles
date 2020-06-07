#!/bin/sh
set -eu

export DEBIAN_FRONTEND=noninteractive

sudo -E apt update
sudo -E apt full-upgrade -y --purge
sudo -E apt autoremove -y --purge
sudo -E apt install -y \
  zsh \
  git \
  golang \
  rsync \
  fzf \
  fd-find \
  neovim \
  jq \
  build-essential \
  cmake

sudo -E apt install -y docker.io
sudo groupadd -f docker
sudo usermod -aG docker "$USER"
newgrp docker

if [ ! -d ~/src/nhooyr/dotfiles ]; then
  mkdir -p ~/src/nhooyr
  git clone https://github.com/nhooyr/dotfiles ~/src/nhooyr/dotfiles
fi
git -C ~/src/nhooyr/dotfiles submodule update --init
git -C ~/src/nhooyr/dotfiles pull
~/src/nhooyr/dotfiles/link.sh

sudo chsh -s "$(command -v zsh)" "$USER"

# https://github.com/neovim/neovim/wiki/Building-Neovim
sudo -E apt install ninja-build gettext libtool libtool-bin autoconf automake cmake g++ pkg-config unzip
if [ ! -d ~/src/neovim/neovim ]; then
  mkdir -p ~/src/neovim
  git clone https://github.com/neovim/neovim ~/src/neovim/neovim
fi
cd ~/src/neovim/neovim
make CMAKE_BUILD_TYPE=RelWithDebInfo
sudo make install
cd -
