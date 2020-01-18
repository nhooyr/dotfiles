#!/usr/bin/env bash

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# Upgrade to debian 10.
sudo apt-get update
sudo apt-get -y upgrade
sudo apt-get -y full-upgrade
sudo apt-get -y --purge autoremove

sudo sed -i s/stretch/buster/g /etc/apt/sources.list
sudo sed -i s/stretch/buster/g /etc/apt/sources.list.d/*

sudo apt-get update
sudo apt-get -y upgrade
sudo apt-get -y full-upgrade
sudo apt-get -y --purge autoremove

sudo apt-get update
sudo apt-get -y install build-essential cmake snapd git software-properties-common gnupg2 fish nodejs fd-find neovim fzf

curl -fsSL https://get.docker.com | bash -s
sudo usermod -aG docker nhooyr

sudo snap install go --classic
sudo snap install hub --classic

curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add -
echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
sudo apt-get update
sudo apt-get install -y yarn

sudo ln -s "$(which /usr/bin/fdfind)" /usr/local/bin/fd > /dev/null || true 

sudo chsh nhooyr -s /usr/bin/fish

# Install latest fzf for --info=hidden.
mkdir -p ~/src/junegunn/fzf
if [[ ! -d ~/src/junegunn/fzf ]]; then
    mkdir -p ~/src/junegunn/fzf
    git clone https://github.com/junegunn/fzf ~/src/junegunn/fzf
fi
cd ~/src/junegunn/fzf
GOPATH=~/.local/share/gopath /snap/bin/go install

cd ~/src/nhooyr/dotfiles
make ensure

if ! grep -q "StreamLocalBindUnlink yes" /etc/ssh/sshd_config; then
  echo "StreamLocalBindUnlink yes" | sudo tee -a /etc/ssh/sshd_config > /dev/null
fi
sudo sed -i "s/#ClientAliveInterval 0/ClientAliveInterval 5/g" /etc/ssh/sshd_config
