#!/bin/sh
set -eu

curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker nhooyr
