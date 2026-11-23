#!/bin/sh
set -eu
cd -- "$(dirname "$0")"
PATH="$PWD/../bin:$PATH"

dotln ./AGENTS.md ~/.codex/AGENTS.md

if [ -e ~/.codex/config.toml ]; then
	merge='(select(fileIndex == 0) // {}) * select(fileIndex == 1)'
	unchanged=$(yq eval-all -o=json "(select(fileIndex == 0) | to_json) == (($merge) | to_json)" \
		~/.codex/config.toml ./config.toml)
	[ "$unchanged" = true ] && exit 0
	yq eval-all -i "$merge" ~/.codex/config.toml ./config.toml
	action=Updated
else
	mkdir -p ~/.codex
	cp ./config.toml ~/.codex/config.toml
	action=Created
fi
printf 'dotfiles: codex: %s: %s %s\n' "${0##*/}" "$action" ~/.codex/config.toml | hpath
