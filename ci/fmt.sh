#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

if [ "${GITHUB_ACTIONS-}" ]; then
	sudo add-apt-repository --yes ppa:fish-shell/release-4
	sudo apt-get install --yes fish shfmt
fi

find . -type f -name '*.fish' -exec fish_indent -w {} +
shfmt -s -w .

if [ "${CI-}" ]; then
	git add --intent-to-add --ignore-removal .

	tput() { command tput -Txterm-256color "$@"; }

	if ! git --no-pager diff --color=always --stat --patch --exit-code; then
		tput bold
		printf '%s %s: unexpected diff\n' "$(printf '%40s' | tr ' ' '^')" "${0##*/}"
		tput sgr0
		exit 1
	fi
fi
