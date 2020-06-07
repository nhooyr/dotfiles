#!/bin/sh
set -eu

sudo apt update

mkdir -p ~/src/nhooyr
if [ ! -d ~/src/nhooyr/dotfiles ]; then
  sudo apt install -y git
  git clone https://github.com/nhooyr/dotfiles ~/src/nhooyr/dotfiles
  ~/src/nhooyr/dotfiles/link.sh
fi

sudo apt -y --purge full-upgrade

cp 99progress-bar /etc/apt/apt.conf.d/

