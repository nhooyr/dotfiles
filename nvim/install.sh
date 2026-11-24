#!/bin/sh
set -eu

cd -- "$(dirname "$0")"
if ! output=$(
	nvim --headless -u NONE -n -i NONE -l - 2>&1 <<'LUA'
dofile('./lua/plugins.lua')
vim.cmd.helptags('doc')
LUA
); then
	printf '%s\n' "$output" >&2
	exit 1
fi
printf 'dotfiles: nvim: %s: Installed plugins and help tags.\n' "${0##*/}"
./app/install.sh --set-defaults
