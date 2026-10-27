#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."

if [ -n "${CI-}" ]; then
	sudo apt-get update
	sudo add-apt-repository --yes ppa:fish-shell/release-4
	sudo apt-get install --yes fish
fi

python3 -m unittest discover -s fish/github-tests
