#!/bin/sh
set -eux

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
  neovim

sudo -E apt install -y docker.io
sudo groupadd -f docker
sudo usermod -aG docker "$USER"
newgrp docker 

mkdir -p ~/src/nhooyr/dotfiles
git clone https://github.com/nhooyr/dotfiles ~/src/nhooyr/dotfiles
~/src/nhooyr/dotfiles/link.sh

chsh -s /bin/zsh
