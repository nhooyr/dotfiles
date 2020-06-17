#!/bin/sh
set -eu

sudo ./ci/link.sh debian/99progress-bar \
  /etc/apt/apt.conf.d/99progress-bar

sudo ./ci/link.sh debian/green/green.sh /usr/local/bin/green.sh
sudo ./ci/cp.sh debian/green/green.timer /etc/systemd/system/green.timer
sudo ./ci/cp.sh debian/green/green.service /etc/systemd/system/green.service
sudo systemctl enable --now green.timer
