#!/bin/sh
set -eu

sudo ./ln.sh debian/99progress-bar \
  /etc/apt/apt.conf.d/99progress-bar

sudo ./ln.sh debian/green/green.sh /usr/local/bin/green.sh
sudo ./cp.sh debian/green/green.timer /etc/systemd/system/green.timer
sudo ./cp.sh debian/green/green.service /etc/systemd/system/green.service
sudo systemctl enable --now green.timer
