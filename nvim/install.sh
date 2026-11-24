#!/bin/sh
set -eu

cd -- "$(dirname "$0")"
if ! output=$(nvim --headless -u NONE -n -i NONE -l ./lua/plugins.lua 2>&1); then
	printf '%s\n' "$output" >&2
	exit 1
fi
printf 'dotfiles: nvim: %s: Installed plugins.\n' "${0##*/}"
./app/install.sh --set-defaults
