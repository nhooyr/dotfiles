#!/bin/sh
set -eu
cd -- "$(dirname "$0")/.."

if [ "${GITHUB_ACTIONS-}" ]; then
	sudo add-apt-repository --yes ppa:fish-shell/release-4
	sudo apt-get install --yes fish cargo zsh fd-find
	sudo install "$(command -v fdfind)" /usr/local/bin/fd
	sudo install "$(command -v ls)" /usr/local/bin/gls
fi

nvim --headless -u NONE -n -i NONE -l ./nvim/lua/plugins.lua

cargo test --manifest-path fish/fzfpaths/Cargo.toml --locked
perl ci/test.pl "$@"
