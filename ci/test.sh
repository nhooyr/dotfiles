#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

if [ "${GITHUB_ACTIONS-}" ]; then
	sudo apt-get update
	sudo apt-get install --yes cargo
fi

cargo test --manifest-path bin/fzf-paths/Cargo.toml --locked
