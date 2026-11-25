#!/bin/sh
set -eu
cd -- "$(dirname "$0")/.."

if [ "${GITHUB_ACTIONS-}" ]; then
	sudo add-apt-repository --yes ppa:fish-shell/release-4
	sudo apt-get install --yes fish shfmt cargo rust-clippy
fi

git ls-files --cached --others --exclude-standard -z -- '*.fish' |
	perl -0ne 'chomp; print "./$_\0" if -f && !-l' | xargs -0 -n1 fish --no-execute
git ls-files --cached --others --exclude-standard -z -- '*.pl' '*.pm' '*.t' |
	perl -0ne 'chomp; print "./$_\0" if -f && !-l' | xargs -0 -r -n1 perl -c

git ls-files --cached --others --exclude-standard -z |
	perl -0ne 'chomp; print "./$_\0" if -f && !-l' |
	xargs -0 shfmt -f=0 | xargs -0 -n1 sh -n
cargo clippy --quiet --manifest-path fzfp/Cargo.toml --locked --all-targets -- -D warnings
