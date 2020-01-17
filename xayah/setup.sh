#!/usr/bin/env bash

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
sudo apt-get update
sudo apt-get -y build-essential cmake snapd git software-properties-common

curl -fsSL https://get.docker.com | bash -s
sudo usermod -aG docker nhooyr

sudo snap install go --classic
sudo snap install hub --classic

sudo apt-add-repository ppa:fish-shell/release-3
sudo apt-get update
sudo apt-get install fish

sudo chsh nhooyr -s /usr/bin/fish
sudo reboot
