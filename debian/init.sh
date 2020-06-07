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
  jq

sudo -E apt install -y docker.io
sudo groupadd -f docker
sudo usermod -aG docker "$USER"
newgrp docker

if [ ! -d ~/src/nhooyr/dotfiles ]; then
  mkdir -p ~/src/nhooyr/dotfiles
  git --recurse-submodules clone https://github.com/nhooyr/dotfiles ~/src/nhooyr/dotfiles
fi
git -C ~/src/nhooyr/dotfiles pull
~/src/nhooyr/dotfiles/link.sh

sudo chsh -s "$(command -v zsh)" "$USER"
