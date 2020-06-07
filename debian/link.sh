#!/bin/sh
set -eu

sudo ./ci/link.sh debian/99progress-bar \
  /etc/apt/apt.conf.d/99progress-bar
