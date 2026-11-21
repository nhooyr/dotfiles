#!/bin/sh
set -eu

cd "$(dirname "$0")"
PATH="$PWD/bin:$PATH"
dotln ./bin ~/.local/bin/dotfiles
dotln ./git/gitconfig ~/.gitconfig
dotln ./git/gitignore ~/.config/git/ignore
dotln ./nvim/init.vim ~/.config/nvim/init.vim
dotln ./nvim/vimrc ~/.vimrc
dotln ./less/lesskey ~/.config/lesskey
dotln ./tmux/tmux.conf ~/.tmux.conf
dotln ./vscode/settings.json ~/Library/Application\ Support/Code/User/settings.json
NO_OVERWRITE=1 dotln ./fish/config.fish ~/.config/fish/config.fish
dotln ./ssh/config ~/.ssh/config
dotln ./ssh/allowed_signers ~/.ssh/allowed_signers
mkdir -p ~/.ssh/sockets
chmod 700 ~/.ssh
chmod 600 ./ssh/config

./fish/fzf-paths/install.sh
./nvim/app/install.sh --set-defaults
./vscode/theme/install.sh
if ! [ -d ~/.config/nvim/pack/github/start/copilot.vim ]; then
	git clone --depth=1 https://github.com/github/copilot.vim.git \
		~/.config/nvim/pack/github/start/copilot.vim
fi
