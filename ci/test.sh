#!/bin/sh
set -eu
cd -- "$(dirname "$0")/.."

if [ "${GITHUB_ACTIONS-}" ]; then
	sudo add-apt-repository --yes ppa:fish-shell/release-4
	sudo apt-get install --yes fish cargo zsh
fi

cargo test --manifest-path fish/fzfpaths/Cargo.toml --locked
perl ci/test.pl "$@"
