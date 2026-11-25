#!/bin/sh
set -eu
cd -- "$(dirname "$0")"
PATH="$PWD/../bin:$PATH"

install_root=~/.local/share
cargo install --path . --root "$install_root" --quiet
printf 'dotfiles: fzfp: %s: Installed %s\n' "${0##*/}" "$install_root/bin/fzfp" | hpath
dotln ./ignore ~/.config/fzfp/ignore
