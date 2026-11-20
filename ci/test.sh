#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

if [ "${GITHUB_ACTIONS-}" ]; then
	sudo apt-get update
	sudo apt-get install --yes rustc
fi

python3 bin/fzf-paths/test.py
