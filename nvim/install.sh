#!/bin/sh
set -eu

cd -- "$(dirname "$0")"
if ! output=$(nvim --headless -u NONE -n -i NONE -l ./lua/plugins.lua install 2>&1); then
	printf '%s\n' "$output" >&2
	exit 1
fi
printf 'dotfiles: nvim: %s: Updated plugins and parsers.\n' "${0##*/}"
./app/install.sh --set-defaults
