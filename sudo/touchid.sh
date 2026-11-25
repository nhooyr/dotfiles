#!/bin/sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
	exec sudo "$0" "$@"
fi

if [ ! -f /etc/pam.d/sudo_local ]; then
	cp /etc/pam.d/sudo_local.template /etc/pam.d/sudo_local
fi

perl -pi -e 's/^#(auth\s+sufficient\s+pam_tid\.so)$/$1/' /etc/pam.d/sudo_local
