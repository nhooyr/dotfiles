#!/bin/sh
set -eu

cd "$(dirname "$0")"
PATH="$PWD/bin:$PATH"
dotln ./bin ~/.local/bin/dotfiles
dotln ./git/gitconfig ~/.gitconfig
dotln ./git/gitignore ~/.config/git/ignore
dotln ./nvim ~/.config/nvim
dotln ./nvim/vimrc ~/.vimrc
dotln ./tmux/tmux.conf ~/.tmux.conf
dotln ./fish/config.fish ~/.config/fish/config.fish
dotln ./vscode/settings.json ~/Library/Application\ Support/Code/User/settings.json
dotln ./ssh/config ~/.ssh/config
dotln ./ssh/allowed_signers ~/.ssh/allowed_signers
mkdir -p ~/.ssh/sockets
chmod 700 ~/.ssh
chmod 600 ~/.ssh/config

./vscode/theme/install.sh
