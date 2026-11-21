#!/bin/sh
set -eu
cd "$(dirname "$0")"
PATH="$PWD/..:$PATH"

install_root=~/.local/share
cargo install --path . --root "$install_root" --quiet
printf 'dotfiles: bin/fzf-paths/%s: Installed %s\n' "${0##*/}" "$install_root/bin/fzf-paths" | hpath
