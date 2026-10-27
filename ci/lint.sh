#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

if [ "${GITHUB_ACTIONS-}" ]; then
	sudo apt-get update
	sudo add-apt-repository --yes ppa:fish-shell/release-4
	sudo apt-get install --yes fish
fi

find . -type f -name '*.fish' -exec fish --no-execute {} \;
