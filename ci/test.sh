#!/bin/sh
set -eu
cd -- "$(dirname "$0")/.."

if [ "${GITHUB_ACTIONS-}" ]; then
	sudo add-apt-repository --yes ppa:fish-shell/release-4
	sudo apt-get install --yes fish cargo
fi

cargo test --manifest-path fish/fzf-paths/Cargo.toml --locked
python3 fish/github-tests/run.py "$@"
