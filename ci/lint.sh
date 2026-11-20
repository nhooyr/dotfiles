#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

if [ "${GITHUB_ACTIONS-}" ]; then
	sudo add-apt-repository --yes ppa:fish-shell/release-4
	sudo apt-get install --yes fish shfmt rustc
fi

find . -type f -name '*.fish' -print0 | xargs -0 -n1 fish --no-execute

shfmt -f=0 . | xargs -0 -n1 sh -n
rust_lint_dir="$(mktemp -d)"
trap 'rm -rf -- "$rust_lint_dir"' EXIT
rustc --edition=2021 -D warnings --emit=metadata -o "$rust_lint_dir/fzf-paths.rmeta" bin/fzf-paths/main.rs
