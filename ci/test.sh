#!/bin/sh
set -eu
cd -- "$(dirname "$0")/.."

if [ "${GITHUB_ACTIONS-}" ]; then
	sudo add-apt-repository --yes ppa:fish-shell/release-4
	sudo apt-get install --yes fish cargo zsh fd-find ripgrep shfmt
	sudo install "$(command -v fdfind)" /usr/local/bin/fd
	sudo install "$(command -v ls)" /usr/local/bin/gls
	# packlockfile and the native directory browser require Neovim 0.13.
	curl --fail --location --output "$RUNNER_TEMP/nvim.tar.gz" \
		https://github.com/neovim/neovim/releases/download/nightly/nvim-linux-x86_64.tar.gz
	tar -xzf "$RUNNER_TEMP/nvim.tar.gz" -C "$RUNNER_TEMP"
	# Match the vendored Fish integration (filter-mode --accept-nth needs 0.68+).
	curl --fail --location --output "$RUNNER_TEMP/fzf.tar.gz" \
		https://github.com/junegunn/fzf/releases/download/v0.75.0/fzf-0.75.0-linux_amd64.tar.gz
	tar -xzf "$RUNNER_TEMP/fzf.tar.gz" -C "$RUNNER_TEMP"
	PATH="$RUNNER_TEMP:$RUNNER_TEMP/nvim-linux-x86_64/bin:$PATH"
fi

nvim --headless -u NONE -n -i NONE -l ./nvim/lua/plugins.lua

test_home=$(mktemp -d)
trap 'rm -rf -- "$test_home"' 0
perl -I./tests -MTestHelpers=test_environment -e '
    %ENV = %{test_environment(shift)};
    exec {$ARGV[0]} @ARGV;
    die "$ARGV[0]: $!\n";
' "$test_home" sh -eu -c '
    cargo test --manifest-path fzfp/Cargo.toml --locked
    perl ci/test.pl "$@"
' sh "$@"
