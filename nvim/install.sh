#!/bin/sh
set -eu

cd -- "$(dirname "$0")"
output=$(nvim --headless -u NONE -n -i NONE -l ./lua/plugins.lua 2>&1) || {
	printf '%s\n' "$output" >&2
	exit 1
}
printf 'dotfiles: nvim: %s: Installed plugins.\n' "${0##*/}"
./app/install.sh --set-defaults
