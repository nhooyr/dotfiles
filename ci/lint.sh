#!/bin/sh
set -eu
cd -- "$(dirname "$0")/.."

if [ "${GITHUB_ACTIONS-}" ]; then
	./ci/install-fish.sh
	sudo apt-get update
	sudo apt-get install --yes shfmt cargo rust-clippy parallel
fi

printf '%s\0' \
	fish 'git ls-files --cached --others --exclude-standard -z -- "*.fish" |
		perl -0ne "chomp; print qq{./\$_\\0} if -f && !-l" | xargs -0 -n1 fish --no-execute' \
	perl 'git ls-files --cached --others --exclude-standard -z -- "*.pl" "*.pm" "*.t" |
		perl -0ne "chomp; print qq{./\$_\\0} if -f && !-l" | xargs -0 -r -n1 perl -c' \
	sh 'git ls-files --cached --others --exclude-standard -z |
		perl -0ne "chomp; print qq{./\$_\\0} if -f && !-l" |
		xargs -0 shfmt -f=0 | xargs -0 -n1 sh -n' \
	clippy 'cargo clippy --quiet --manifest-path fzfp/Cargo.toml --locked --all-targets -- -D warnings' |
	PARALLEL_SHELL=/bin/sh parallel --plain --null -N 2 --jobs 4 --line-buffer --tagstring '[{1}]' 'sh -ec {2} 2>&1'
