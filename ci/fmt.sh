#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

if [ "${GITHUB_ACTIONS-}" ]; then
	sudo apt-get update
	sudo add-apt-repository --yes ppa:fish-shell/release-4
	sudo apt-get install --yes fish shfmt
fi

find . -type f -name '*.fish' -exec fish_indent -w {} +
shfmt -s -w .

if [ "${CI-}" ]; then
	git ls-files --other --exclude-standard | xargs -r git add --intent-to-add

	git -c color.ui=always diff --stat
	if ! git -c color.ui=always diff --exit-code; then
		tput smul
		tput sitm
		tput bold
		printf "%s %s: unexpected diff\n" "$(printf '%40s' | tr ' ' '^')" "$(basename "$0")"
		tput sgr0
		exit 1
	fi
fi
