#!/bin/sh
set -eu
cd -- "$(dirname "$0")"
PATH="$PWD/bin:$PATH"

dotln ./bin ~/.local/bin/dotfiles
dotln ./less/lesskey ~/.config/lesskey
dotln ./bat ~/.config/bat
dotln ./tmux/tmux.conf ~/.tmux.conf
dotln ./ssh/config ~/.ssh/config
dotln ./ssh/allowed_signers ~/.ssh/allowed_signers
mkdir -p ~/.ssh/sockets
chmod 700 ~/.ssh
chmod 600 ./ssh/config

./git/install.sh
./fzfp/install.sh
./fish/install.sh
./nvim/install.sh
./codex/install.sh
./vscode/install.sh
./bat/install.sh
