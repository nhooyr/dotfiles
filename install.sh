#!/bin/sh
set -eu
cd -- "$(dirname "$0")"
PATH="$PWD/bin:$PATH"

dotln ./bin ~/.local/bin/dotfiles
dotln ./less/lesskey ~/.config/lesskey
dotln ./tmux/tmux.conf ~/.tmux.conf

./ssh/install.sh
./git/install.sh
./fzfp/install.sh
./fish/install.sh
./nvim/install.sh
./codex/install.sh
./vscode/install.sh
./bat/install.sh
