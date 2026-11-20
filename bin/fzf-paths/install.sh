#!/bin/sh
set -eu
cd "$(dirname "$0")"
PATH="$PWD/..:$PATH"

target=~/.local/share/bin/fzf-paths
if [ -x "$target" ] && [ "$target" -nt main.rs ] && [ "$target" -nt install.sh ]; then
	printf 'dotfiles: bin/fzf-paths/%s: Already up to date: %s\n' "${0##*/}" "$target" | hpath
	exit 0
fi

mkdir -p "${target%/*}"
temporary="$(mktemp "$target.XXXXXX")"
trap 'rm -f -- "$temporary"' EXIT
rustc --edition=2021 -O main.rs -o "$temporary"
mv -f -- "$temporary" "$target"
printf 'dotfiles: bin/fzf-paths/%s: Installed %s\n' "${0##*/}" "$target" | hpath
